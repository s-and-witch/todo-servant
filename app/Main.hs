{-# LANGUAGE DataKinds #-}
{-# LANGUAGE  TypeOperators #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE RecordWildCards #-}
module Main where

import Servant
import Data.Aeson
import Network.Wai.Handler.Warp
import GHC.Generics 
import Control.Concurrent.STM
import Control.Concurrent.Async
import Data.IORef
import Control.Monad.IO.Class 
import Data.HashMap.Strict as HashMap
import Control.Concurrent
import System.Random
import Control.Monad


data Status 
  = Finished { result :: Int } 
  | InProcess
  deriving stock Generic
  deriving anyclass (FromJSON, ToJSON)

type StartTask 
  =  "task" 
  :> "start" 
  :> ReqBody '[JSON] Int 
  :> Post '[JSON] ID

type CheckTask
  =  "task"
  :> "status" 
  :> Capture "id" ID
  :> Get '[JSON] Status

type Api = StartTask :<|> CheckTask

type ID = Int

type Counter = IORef ID

data Task = Task { taskData :: Int, taskId :: ID }

api :: Proxy Api
api = Proxy

app :: TQueue Task -> Counter -> TVar (HashMap ID Status) -> Application
app tasksQueue counter tasks = serve api 
  $    startTask tasksQueue counter
  :<|> checkTask tasks

main :: IO ()
main = do
  tasksQueue <- newTQueueIO
  tasks <- newTVarIO empty
  counter <- newIORef 1
  tasksExecutor tasksQueue tasks 
    `race_` 
    run 8081 (app tasksQueue counter tasks)


startTask :: TQueue Task -> Counter -> Int -> Handler Int
startTask tasksQueue counter taskData = do
    taskId <- newId
    let task = Task{ taskData, taskId }
    liftIO . atomically $ writeTQueue tasksQueue task
    pure taskId
  where
    newId = liftIO do
      taskId <- readIORef counter
      modifyIORef counter (+1)
      pure taskId

checkTask :: TVar (HashMap ID Status) -> Int -> Handler Status
checkTask tasks taskId = do
  status <- liftIO . atomically $ HashMap.lookup taskId <$> readTVar tasks 
  case status of
    Nothing -> throwError noTaskError
    Just sta -> pure sta
  where
    noTaskError = err404 { errBody = "Sorry, but there is no this task" }


tasksExecutor :: TQueue Task -> TVar (HashMap ID Status) -> IO ()
tasksExecutor tasksQueue tasks = forever do registryTask >>= startTask
  where
    registryTask = atomically do
      task@(Task _ taskId) <- readTQueue tasksQueue
      modifyTVar tasks (insert taskId InProcess)
      pure task
    startTask Task{..} = forkIO do
      threadDelay =<< randomRIO (4 * 1000000, 20 * 1000000)
      atomically do
        modifyTVar tasks (insert taskId (Finished (taskData * 2)))