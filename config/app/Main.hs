{-# LANGUAGE OverloadedStrings #-}

module Main where

import Prelude hiding (readFile)
import Data.ByteString (readFile)
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Yaml as Yaml
import Data.Yaml ((.:), (.:?), (.!=))

import Shelly
import System.Process (waitForProcess, terminateProcess, runProcess)
import System.Exit (ExitCode (ExitFailure, ExitSuccess), exitWith)
import System.Posix.Signals (installHandler, Handler (Catch), sigTERM)
import System.Environment (getArgs)


data Config =
  Config {
    users :: [User]
  , hostKeys :: Maybe HostKeys
  } deriving (Eq, Show)

instance Yaml.FromJSON Config where
  parseJSON (Yaml.Object v) = Config
    <$> v .: "users"
    <*> v .:? "hostKeys"

data User =
  User {
    name :: Text
  , password :: Maybe Text
  , keys :: [Text]
  } deriving (Eq, Show)

instance Yaml.FromJSON User where
  parseJSON (Yaml.Object u) = User
    <$> u .: "name"
    <*> u .:? "password"
    <*> u .:? "keys" .!= []

data HostKeys =
  HostKeys {
    rsa1 :: Maybe Text
  , rsa :: Maybe Text
  , dsa :: Maybe Text
  , ecdsa :: Maybe Text
  , ed25519 :: Maybe Text
  } deriving (Eq, Show)

instance Yaml.FromJSON HostKeys where
  parseJSON (Yaml.Object k) = HostKeys
    <$> k .:? "rsa1"
    <*> k .:? "rsa"
    <*> k .:? "dsa"
    <*> k .:? "ecdsa"
    <*> k .:? "ed25519"


type Path = Text
data Action = WriteFile Path Text | RunCommand Text [Text] | ChangePassword Text Text
  deriving (Eq, Show)


sshd_config = Text.pack $ unlines [
  "Subsystem sftp internal-sftp",
  "Match group sftp",
  "       PubkeyAuthentication yes",
  "       PasswordAuthentication yes",
  "       X11Forwarding no",
  "       PermitTunnel no",
  "       AllowTcpForwarding no",
  "       AllowAgentForwarding no",
  "       PermitOpen none",
  "       ChrootDirectory /sftp",
  "       ForceCommand internal-sftp"
  ]

setupCommands = [
    WriteFile "/etc/ssh/sshd_config" sshd_config,
    RunCommand "addgroup" ["sftp"],
    RunCommand "chown" ["root:sftp", "/sftp"],
    RunCommand "chown" ["root:sftp", "/sftp/data"],
    RunCommand "chmod" ["755", "/sftp"],
    RunCommand "chmod" ["2775", "/sftp/data"]
  ]

hostKeysCommands :: Maybe HostKeys -> [Action]
hostKeysCommands Nothing = [RunCommand "ssh-keygen" ["-A"]]
hostKeysCommands (Just hk) =
  concatMap (uncurry doFile) [("rsa1", rsa1), ("rsa", rsa), ("dsa", dsa), ("ecdsa", ecdsa), ("ed25519", ed25519)]
    where
      doFile n f = maybe [] (\text -> [WriteFile (fileName n) text, RunCommand "chmod" ["400", fileName n]]) $ f hk
      fileName keyType = (Text.concat ["/etc/ssh/ssh_host_", keyType, "_key"])

userCommands :: User -> [Action]
userCommands u = doCreate ++ doKeys (keys u) ++ doPasswd (password u)
  where
    doCreate = [RunCommand "adduser" ["-D", "-G", "sftp", "-s", "/sbin/nologin", "-H", "-h", "/data", name u]]
    doPasswd Nothing = []
    doPasswd (Just pw) = [ChangePassword (name u) pw]
    doKeys [] = []
    doKeys keys = [
        RunCommand "mkdir" ["-p", Text.concat ["/home/", name u, "/.ssh"]],
        WriteFile (Text.concat ["/home/", name u, "/.ssh/authorized_keys"]) (Text.concat keys)
      ]

actions config = setupCommands ++ (hostKeysCommands $ hostKeys config) ++ (concatMap userCommands $ users config)

exec :: Action -> Sh ()
exec (RunCommand cmd args) = run_ (fromText cmd) args
exec (WriteFile filename content) = writefile (fromText filename) content
exec (ChangePassword user pass) = do
  setStdin (Text.concat [user, ":", pass])
  run_ "chpasswd" [] 


main :: IO ()
main = do
    args <- getArgs
    let fileName = if (null args) then "/config.yml" else (args !! 0)
    yaml <- readFile fileName
    let config = maybe (error "Couldn't parse config") id (Yaml.decode yaml :: Maybe Config)

    shelly $ mapM_ exec $ actions config

    sshd <- runProcess "/usr/sbin/sshd" ["-e", "-D", "-f", "/etc/ssh/sshd_config"] Nothing Nothing Nothing Nothing Nothing
    installHandler sigTERM (Catch $ terminateProcess sshd) Nothing
    exitCode <- waitForProcess sshd
    exitWith exitCode
