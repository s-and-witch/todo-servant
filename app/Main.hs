{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}
module Main where

import Servant
import Data.Aeson
import Network.Wai.Handler.Warp
import GHC.Generics (Generic)
import Control.Concurrent.STM
import Control.Concurrent.Async
import Data.IORef
import Control.Monad.IO.Class 
import Data.HashMap.Strict as HashMap
import Control.Concurrent
import System.Random


data Status 
  = Finished { result :: Int } 
  | InProcess
  deriving stock Generic
  deriving anyclass (FromJSON, ToJSON)

type StartTask 
  =  "task" 
  :> "start" 
  :> ReqBody '[JSON] Int 
  :> Post '[JSON] Int

type CheckTask
  =  "task"
  :> "status"
  :> Capture "id" Int
  :> Get '[JSON] Status

type Api = StartTask :<|> CheckTask

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

type ID = Int

type Counter = IORef ID

data Task = Task { taskData :: Int, taskId :: ID }

startTask :: TQueue Task -> Counter -> Int -> Handler Int
startTask tasksQueue counter taskData = do
  taskId <- liftIO $ readIORef counter
  liftIO $ modifyIORef counter (+1)
  let task = Task{ taskData, taskId }
  liftIO . atomically $ writeTQueue tasksQueue task
  pure taskId

checkTask :: TVar (HashMap ID Status) -> Int -> Handler Status
checkTask tasks id = do
  status <- liftIO . atomically $ HashMap.lookup id <$> readTVar tasks 
  case status of
    Nothing -> throwError noTaskError
    Just sta -> pure sta
  where
    noTaskError = err404 { errBody = "Sorry, but there is no this task" }


tasksExecutor :: TQueue Task -> TVar (HashMap ID Status) -> IO ()
tasksExecutor tasksQueue tasks = loop
  where
    loop = do
      (Task taskData id) <- atomically do
        task@(Task _ id) <- readTQueue tasksQueue
        modifyTVar tasks (insert id InProcess)
        pure task

      forkIO do
        threadDelay =<< randomRIO (1 * 1000000, 20 * 1000000)
        atomically do
          modifyTVar tasks (insert id (Finished (taskData * 2)))

      loop