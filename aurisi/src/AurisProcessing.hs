{-# LANGUAGE
    TypeApplications
#-}
module AurisProcessing
    ( runProcessing
    ) where

import           RIO
import           Data.PUS.GlobalState
import           Data.PUS.MissionSpecific.Definitions
                                                ( PUSMissionSpecific )
import           Data.PUS.Config                ( Config(cfgDataBase) )
import           Control.PUS.Classes            ( setDataModel )

import           Interface.Interface            ( Interface
                                                , ifRaiseEvent
                                                )
import           Interface.Events               ( IfEvent(EventPUS) )
import           Interface.CoreProcessor        ( runCoreThread
                                                , InterfaceAction
                                                )

import           AurisConfig                    ( AurisConfig
                                                    ( aurisLogLevel
                                                    , aurisPusConfig
                                                    )
                                                , configPath
                                                , defaultMIBFile
                                                , convLogLevel
                                                )

import           System.Directory               ( getHomeDirectory )
import           System.FilePath                ( (</>) )

import           GUI.MessageDisplay             ( messageAreaLogFunc )
import           GUI.MainWindow                 ( MainWindow
                                                , mwMessageDisplay
                                                , mwInitialiseDataModel
                                                )
import           Data.GI.Gtk.Threading          ( postGUIASync )
import           Application.Chains             ( runChains )
import           Application.DataModel          ( loadDataModelDef
                                                , LoadFrom
                                                    ( LoadFromSerialized
                                                    , LoadFromMIB
                                                    )
                                                )
import           Verification.Processor         ( processVerification )
import           Persistence.DbProcessing       ( startDbProcessing )



runProcessing
    :: AurisConfig
    -> PUSMissionSpecific
    -> Maybe FilePath
    -> Interface
    -> MainWindow
    -> TBQueue InterfaceAction
    -> IO ()
runProcessing cfg missionSpecific mibPath interface mainWindow coreQueue = do
    defLogOptions <- logOptionsHandle stdout True
    let logOptions =
            setLogMinLevel (convLogLevel (aurisLogLevel cfg)) defLogOptions
    
    -- start with the logging 
    withLogFunc logOptions $ \logFunc -> do
    
        -- First, we create the databas
        dbBackend <- startDbProcessing (cfgDataBase (aurisPusConfig cfg))
        
        -- Add the logging function to the GUI
        let logf = logFunc
                <> messageAreaLogFunc (mainWindow ^. mwMessageDisplay)
            
        -- Create a new 'GlobalState' for the processing
        state <- newGlobalState (aurisPusConfig cfg)
                                missionSpecific
                                logf
                                (ifRaiseEvent interface . EventPUS)
                                (Just dbBackend)

        void $ runRIO state $ do
          -- first, try to load a data model or import a MIB
            logInfo "Loading Data Model..."

            home <- liftIO getHomeDirectory
            let path = case mibPath of
                    Just p  -> LoadFromMIB p serializedPath
                    Nothing -> LoadFromSerialized serializedPath
                serializedPath = home </> configPath </> defaultMIBFile

            model <- loadDataModelDef path
            env   <- ask
            setDataModel env model

            logInfo "Initialising User Interface with Data Model..."
            liftIO $ postGUIASync $ mwInitialiseDataModel mainWindow model

            logInfo "Starting TM and TC chains..."

            -- Start the core processing thread (commands from GUI)
            void $ async $ runCoreThread coreQueue

            -- Start the TC verification processor 
            void $ async $ processVerification (glsVerifCommandQueue env)

            -- run all processing chains (TM and TC) as well as the 
            -- interface threads 
            runChains missionSpecific



-- withLogging :: AurisConfig -> MainWindow -> (LogFunc -> IO ()) -> IO ()
-- withLogging cfg mainWindow app = do
--   defLogOptions <- logOptionsHandle stdout True
--   let logOptions =
--         setLogMinLevel (convLogLevel (aurisLogLevel cfg)) defLogOptions

--   withLogFunc logOptions $ \logFn -> do
--     let logFn' = logFn <> messageAreaLogFunc mainWindow
--     case (aurisDatabase cfg, aurisDbLogLevel cfg) of
--       (Just dbPath, Just logLvl) -> withDatabaseLogger
--         dbPath (convLogLevel logLvl) $ app . mappend logFn'
--       _ -> app logFn'
