{-# LANGUAGE OverloadedStrings
    , GeneralizedNewtypeDeriving
    , BangPatterns
    , NoImplicitPrelude
    , DataKinds
    , TemplateHaskell
#-}
module Data.MIB.PCF
    ( PCFentry(..)
    , loadFromFile
    , getPCFMap
    , getEndian

    , pcfName
    , pcfDescr
    , pcfPID
    , pcfUnit
    , pcfPTC
    , pcfPFC
    , pcfWidth
    , pcfValid
    , pcfRelated
    , pcfCateg
    , pcfNatur
    , pcfCurTx
    , pcfInter
    , pcfUscon
    , pcfDecim
    , pcfParVal
    , pcfSubSys
    , pcfValPar
    , pcfSpType
    , pcfCorr
    , pcfOBTID
    , pcfDARC
    , pcfEndian

    )
where

import           RIO

import           Control.Lens                   ( makeLenses )

import qualified Data.ByteString.Lazy          as BL
import qualified Data.ByteString.Lazy.Char8    as BC
import qualified Data.Text                     as T
import           Data.Csv
import           Data.Char
import qualified Data.Vector                   as V
import           Data.HashMap.Lazy             as HM

import           System.FilePath
import           System.Directory

import           Data.MIB.Types


data PCFentry = PCFentry {
    _pcfName :: !Text,
    _pcfDescr :: !Text,
    _pcfPID :: !Text,
    _pcfUnit :: !Text,
    _pcfPTC :: !Int,
    _pcfPFC :: !Int,
    _pcfWidth :: !Text,
    _pcfValid :: !Text,
    _pcfRelated :: !Text,
    _pcfCateg :: Maybe Char,
    _pcfNatur :: Maybe Char,
    _pcfCurTx :: !Text,
    _pcfInter :: !Text,
    _pcfUscon :: !Text,
    _pcfDecim :: !Text,
    _pcfParVal :: !Text,
    _pcfSubSys :: !Text,
    _pcfValPar :: DefaultTo 1,
    _pcfSpType :: !Text,
    _pcfCorr :: Maybe Char,
    _pcfOBTID :: Maybe Int,
    _pcfDARC :: Maybe Char,
    _pcfEndian :: Maybe Char
} deriving (Show, Read)
makeLenses ''PCFentry


getEndian :: PCFentry -> Char
getEndian PCFentry { _pcfEndian = Just x }  = x
getEndian PCFentry { _pcfEndian = Nothing } = 'B'



instance Eq PCFentry where
    pcf1 == pcf2 = _pcfName pcf1 == _pcfName pcf2



instance FromRecord PCFentry where
    parseRecord v
        | V.length v >= 23
        = PCFentry
            <$> v
            .!  0
            <*> v
            .!  1
            <*> v
            .!  2
            <*> v
            .!  3
            <*> v
            .!  4
            <*> v
            .!  5
            <*> v
            .!  6
            <*> v
            .!  7
            <*> v
            .!  8
            <*> v
            .!  9
            <*> v
            .!  10
            <*> v
            .!  11
            <*> v
            .!  12
            <*> v
            .!  13
            <*> v
            .!  14
            <*> v
            .!  15
            <*> v
            .!  16
            <*> v
            .!  17
            <*> v
            .!  18
            <*> v
            .!  19
            <*> v
            .!  20
            <*> v
            .!  21
            <*> v
            .!  22
        | V.length v >= 19
        = PCFentry
            <$> v
            .!  0
            <*> v
            .!  1
            <*> v
            .!  2
            <*> v
            .!  3
            <*> v
            .!  4
            <*> v
            .!  5
            <*> v
            .!  6
            <*> v
            .!  7
            <*> v
            .!  8
            <*> v
            .!  9
            <*> v
            .!  10
            <*> v
            .!  11
            <*> v
            .!  12
            <*> v
            .!  13
            <*> v
            .!  14
            <*> v
            .!  15
            <*> v
            .!  16
            <*> v
            .!  17
            <*> v
            .!  18
            <*> pure Nothing
            <*> pure Nothing
            <*> pure Nothing
            <*> pure Nothing
        | otherwise
        = mzero



myOptions :: DecodeOptions
myOptions = defaultDecodeOptions { decDelimiter = fromIntegral (ord '\t') }


fileName :: FilePath
fileName = "pcf.dat"


loadFromFile
    :: (MonadIO m, MonadReader env m, HasLogFunc env, HasCallStack)
    => FilePath
    -> m (Either Text (Vector PCFentry))
loadFromFile mibPath = do
    let file = mibPath </> fileName
    ex <- liftIO $ doesFileExist file
    if ex
        then do
            logInfo $ "Reading file " <> display (T.pack fileName)
            content <- liftIO $ BL.readFile file
            logInfo "File read. Parsing..."
            let r = decodeWith myOptions NoHeader (BC.filter isAscii content)
            logInfo "Parsing Done."
            case r of
                Left  err -> pure $ Left (T.pack err)
                Right x   -> pure $ Right x
        else do
            return $! Left $ "File " <> T.pack file <> " does not exist."


getPCFMap :: Vector PCFentry -> HashMap Text PCFentry
getPCFMap = V.foldl (\m e -> HM.insert (_pcfName e) e m) HM.empty