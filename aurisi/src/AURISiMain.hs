{-# LANGUAGE
  TemplateHaskell
  , DataKinds
  , TypeOperators
  , OverloadedLabels
#-}
module Main where

import qualified Data.Text.IO                  as T
import           RIO
import qualified RIO.Text                      as T

import           Options.Generic

import           AurisConfig
import           AurisStart

import           GHC.Conc                       ( getNumProcessors
                                                , setNumCapabilities
                                                )
import           System.Directory               ( doesFileExist )

import           Version


data Options w = Options
    { version     :: w ::: Bool <?> "Print version information"
    , config      :: w ::: Maybe String <?> "Specify a config file"
    , writeconfig :: w ::: Bool <?> "Write the default config to a file"
    , importmib
          :: w ::: Maybe FilePath <?> "Specifies a MIB directory. An import is done and the binary version of the MIB is stored for faster loading"
    }
    deriving Generic

instance ParseRecord (Options Wrapped)
deriving instance Show (Options Unwrapped)




main :: IO ()
main = do
    np <- getNumProcessors
    setNumCapabilities np

    opts <- unwrapRecord "AURISi"
    if version opts
        then T.putStrLn aurisVersion
        else if writeconfig opts
            then do
                writeConfigJSON defaultConfig "DefaultConfig.json"
                T.putStrLn "Wrote default config to file 'DefaultConfig.json'"
                exitSuccess
            else do
                cfg <- case config opts of
                    Nothing -> do
                        ex <- doesFileExist defaultConfigFileName
                        if ex
                            then do
                                T.putStrLn
                                    $  "Loading default config from "
                                    <> T.pack defaultConfigFileName
                                    <> "..."
                                res <- loadConfigJSON defaultConfigFileName
                                case res of
                                    Left err -> do
                                        T.putStrLn
                                            $  "Error loading config: "
                                            <> err
                                        exitFailure
                                    Right c -> pure c
                            else do
                                T.putStrLn "Using default config"
                                return defaultConfig
                    Just path -> do
                        T.putStrLn
                            $  "Loading configuration from file "
                            <> T.pack path
                        res <- loadConfigJSON path
                        case res of
                            Left err -> do
                                T.putStrLn $ "Error loading config: " <> err
                                exitFailure
                            Right c -> pure c

                let mibPath = importmib opts
                runApplication cfg mibPath





