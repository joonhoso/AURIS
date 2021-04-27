{-|
Module      : Data.TM.Value
Description : Specifies a parameter value
Copyright   : (c) Michael Oswald, 2019
License     : BSD-3
Maintainer  : michael.oswald@onikudaki.net
Stability   : experimental
Portability : POSIX

This module is for handling of values at application level. This is not to be confused with
the Data.PUS.Value which is used on the encoding/decoding layer.
-}
{-# LANGUAGE
    OverloadedStrings
    , BangPatterns
    , NoImplicitPrelude
    , DataKinds
    , DeriveGeneric
    , GeneralizedNewtypeDeriving
    , TemplateHaskell
#-}
module Data.TM.Value
    ( TMValueSimple(..)
    , TMValue(..)
    , compareVal
    , isNumeric
    , Data.TM.Value.isValid
    , setValidity
    , tmvalValue
    , tmvalValidity
    , NumType(..)
    , Radix(..)
    , parseShortTextToValueSimple
    , parseShortTextToValue
    , parseShortTextToDouble
    , parseShortTextToInt64
    , parseShortTextToWord64
    , charToType
    , charToRadix
    , nullValue
    , getInt
    , getDouble
    , toDouble
    ) where

import           RIO                     hiding ( many )
import           RIO.List.Partial               ( head )
import qualified RIO.Text                      as T
import qualified RIO.ByteString                as B
import qualified RIO.Set                       as S
import           Control.Lens                   ( makeLenses )

import           Data.Text.Short                ( ShortText
                                                , toText
                                                , fromText
                                                )
import           Codec.Serialise
import           Data.Aeson
import           Data.ByteString.Base64.Type

import           Data.TM.Validity

import           General.Time
import           General.Types
import           General.PUSTypes
import           General.Chunks
import           General.Hexdump

import           Text.Megaparsec               as M
import           Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer    as L

import           Numeric


-- | The numerical type if it is a numerical value
data NumType =
    NumInteger
    | NumUInteger
    | NumDouble
    deriving (Eq, Ord, Enum, Show, Read, Generic)

instance NFData NumType
instance Serialise NumType
instance FromJSON NumType
instance ToJSON NumType where
    toEncoding = genericToEncoding defaultOptions

type Parser = Parsec Void Text


-- | Converst from a Char to a 'NumType' according to the SCOS-2000 MIB ICD 6.9
{-# INLINABLE charToType #-}
charToType :: Char -> NumType
charToType 'I' = NumInteger
charToType 'U' = NumUInteger
charToType 'R' = NumDouble
charToType _   = NumInteger


-- | parses a 'ShortText' to a double value. It takes the 'NumType' and 'Radix' to determine
-- the format the value is and returns a 'Double' value
{-# INLINABLE parseShortTextToDouble #-}
parseShortTextToDouble :: NumType -> Radix -> ShortText -> Either Text Double
parseShortTextToDouble typ radix x =
  -- trace ("parseTextToDouble: " <> T.pack (show typ ++ " " ++ show radix ++ show x)) $
    case parse (doubleParser typ radix) "" (toText x) of
        Left err ->
            Left
                $  "Could not parse '"
                <> toText x
                <> "' into Double: "
                <> T.pack (errorBundlePretty err)
        Right xval -> Right xval


{-# INLINABLE doubleParser #-}
doubleParser :: NumType -> Radix -> Parser Double
doubleParser NumInteger  _       = fromIntegral <$> signedInteger
doubleParser NumUInteger Decimal = fromIntegral <$> integer
doubleParser NumUInteger Hex     = fromIntegral <$> hexInteger
doubleParser NumUInteger Octal   = fromIntegral <$> octInteger
doubleParser NumDouble _ =
    M.try double <|> fromIntegral <$> signedInteger


double :: Parser Double
double =
    M.try (L.signed space L.float)
        <|> (fromIntegral <$> L.signed space integer)

integer :: Parser Int64
integer = L.lexeme space L.decimal

uInteger :: Parser Word64
uInteger = L.lexeme space L.decimal

signedInteger :: Parser Int64
signedInteger = L.signed space integer

hexInteger :: Parser Word64
hexInteger = L.lexeme space L.hexadecimal

octInteger :: Parser Word64
octInteger = L.lexeme space L.octal


-- | parses a 'ShortText' to a integer value. It takes the 'NumType' and 'Radix' to determine
-- the format the value is and returns a 'Int64' value
parseShortTextToInt64 :: NumType -> Radix -> ShortText -> Either Text Int64
parseShortTextToInt64 typ radix x =
  -- trace ("parseShortTextToInt64: " <> T.pack (show typ ++ " " ++ show radix ++ show x)) $
    case parseMaybe (intParser typ radix) (toText x) of
        Nothing ->
            Left
                $  "Could not parse '"
                <> toText x
                <> "' into Int64 (type="
                <> T.pack (show typ)
                <> ", radix= "
                <> T.pack (show radix)
                <> ")"
        Just xval -> Right xval


-- | parses a 'ShortText' to a integer value. It takes the 'NumType' and 'Radix' to determine
-- the format the value is and returns a 'Int64' value
parseShortTextToWord64 :: NumType -> Radix -> ShortText -> Either Text Word64
parseShortTextToWord64 typ radix x =
  -- trace ("parseShortTextToInt64: " <> T.pack (show typ ++ " " ++ show radix ++ show x)) $
    case parseMaybe (uintParser typ radix) (toText x) of
        Nothing ->
            Left
                $  "Could not parse '"
                <> toText x
                <> "' into UInt64 (type="
                <> T.pack (show typ)
                <> ", radix= "
                <> T.pack (show radix)
                <> ")"
        Just xval -> Right xval


intParser :: NumType -> Radix -> Parser Int64
intParser NumInteger  Decimal = signedInteger
intParser NumInteger  Hex     = L.signed space L.hexadecimal
intParser NumInteger  Octal   = L.signed space L.octal
intParser NumUInteger Decimal = integer
intParser NumUInteger Hex     = fromIntegral <$> hexInteger
intParser NumUInteger Octal   = fromIntegral <$> octInteger
intParser NumDouble _ =
    truncate <$> M.try double <|> signedInteger

uintParser :: NumType -> Radix -> Parser Word64
uintParser NumInteger  Decimal = fromIntegral <$> signedInteger
uintParser NumInteger  Hex     = L.signed space L.hexadecimal
uintParser NumInteger  Octal   = L.signed space L.octal
uintParser NumUInteger Decimal = L.decimal
uintParser NumUInteger Hex     = hexInteger
uintParser NumUInteger Octal   = octInteger
uintParser NumDouble _ = truncate <$> M.try double <|> L.decimal

-- | A simple value, without a validity. Contains the specified value
data TMValueSimple =
    -- | the value is a singed integer
    TMValInt !Int64
    -- | the value is a unsinged integer
    | TMValUInt !Word64
    -- | the value is a 'Double'
    | TMValDouble !Double
    -- | the value is a time value
    | TMValTime !SunTime
    -- | the value is a string
    | TMValString !ShortText
    -- | the value is an octet string (binary value)
    | TMValOctet !ByteString
    -- | A value containing nothing
    | TMValNothing
    deriving(Show, Generic)

-- | A simple null value
{-# INLINABLE nullValueSimple #-}
nullValueSimple :: TMValueSimple
nullValueSimple = TMValUInt 0

instance NFData TMValueSimple
instance Serialise TMValueSimple

-- | Compare two values. Since we also cover non-numeric values,
-- the function returns a 'Maybe' 'Ordering'. If the values cannot
-- be compared, Nothing is returned.
{-# INLINABLE compareVal #-}
compareVal :: TMValueSimple -> TMValueSimple -> Maybe Ordering
compareVal (TMValInt    x) (TMValInt    y) = Just $ compare x y
compareVal (TMValUInt   x) (TMValUInt   y) = Just $ compare x y
compareVal (TMValDouble x) (TMValDouble y) = Just $ compare x y
compareVal (TMValTime   x) (TMValTime   y) = Just $ compare x y
compareVal (TMValString x) (TMValString y) = Just $ compare x y
compareVal (TMValOctet  x) (TMValOctet  y) = Just $ compare x y

compareVal (TMValInt    x) (TMValDouble y) = Just $ compare (fromIntegral x) y
compareVal (TMValUInt   x) (TMValDouble y) = Just $ compare (fromIntegral x) y
compareVal (TMValDouble x) (TMValInt    y) = Just $ compare x (fromIntegral y)
compareVal (TMValDouble x) (TMValUInt   y) = Just $ compare x (fromIntegral y)

compareVal _               _               = Nothing

instance Eq TMValueSimple where
    val1 == val2 = case compareVal val1 val2 of
        Just EQ -> True
        _       -> False

instance Ord TMValueSimple where
    compare v1 v2 = fromMaybe LT $ compareVal v1 v2

instance FromJSON TMValueSimple where
    parseJSON = withObject "TMValueSimple" $ \o -> asum
        [ TMValInt <$> o .: "tmValInt"
        , TMValUInt <$> o .: "tmValUInt"
        , TMValDouble <$> o .: "tmValDouble"
        , TMValTime <$> o .: "tmValTime"
        , TMValString <$> o .: "tmValString"
        , TMValOctet . getByteString64 <$> o .: "tmValOctet"
        ]

instance ToJSON TMValueSimple where
    toJSON (TMValInt    x) = object ["tmValInt" .= x]
    toJSON (TMValUInt   x) = object ["tmValUInt" .= x]
    toJSON (TMValDouble x) = object ["tmValDouble" .= x]
    toJSON (TMValTime   x) = object ["tmValTime" .= x]
    toJSON (TMValString x) = object ["tmValString" .= x]
    toJSON (TMValOctet  x) = object ["tmValOctet" .= makeByteString64 x]
    toJSON TMValNothing    = object ["tmValNothing" .= ("" :: Text)]
    toEncoding (TMValInt    x) = pairs ("tmValInt" .= x)
    toEncoding (TMValUInt   x) = pairs ("tmValUInt" .= x)
    toEncoding (TMValDouble x) = pairs ("tmValDouble" .= x)
    toEncoding (TMValTime   x) = pairs ("tmValTime" .= x)
    toEncoding (TMValString x) = pairs ("tmValString" .= x)
    toEncoding (TMValOctet  x) = pairs ("tmValOctet" .= makeByteString64 x)
    toEncoding TMValNothing    = pairs ("tmValNothing" .= ("" :: Text))


instance Display TMValueSimple where
    display (TMValInt    x) = display x
    display (TMValUInt   x) = display x
    display (TMValDouble x) = display x
    display (TMValTime   x) = display x
    display (TMValString x) = display (toText x)
    display (TMValOctet  x) = display (hexdumpBS x)
    display TMValNothing    = ""


-- | parses a 'ShortText' to a integer value. It takes the 'PTC' and 'PFC' type descriptors
-- and returns a 'TMValueSimple' with the specified type
parseShortTextToValueSimple
    :: PTC -> PFC -> ShortText -> Either Text TMValueSimple
parseShortTextToValueSimple ptc pfc x =
    case parseMaybe (tmValueParser ptc pfc) (toText x) of
        Nothing ->
            Left
                $  "Could not parse '"
                <> toText x
                <> "' into TMValueSimple (PTC="
                <> T.pack (show ptc)
                <> ", PFC="
                <> T.pack (show pfc)
                <> ")"
        Just xval -> Right xval

-- | parses a 'ShortText' to a integer value. It takes the 'PTC' and 'PFC' type descriptors
-- and returns a 'TMValue' with the specified type and a clearValidity
parseShortTextToValue
    :: PTC -> PFC -> ShortText -> Either Text TMValue
parseShortTextToValue ptc pfc x =
    case parseShortTextToValueSimple ptc pfc x of
        Left  err -> Left err
        Right val -> Right (TMValue val clearValidity)



{-# INLINABLE tmValueParser #-}
tmValueParser :: PTC -> PFC -> Parser TMValueSimple
tmValueParser (PTC ptc) (PFC pfc)
    | ptc == 1 || ptc == 2 || ptc == 3
    = TMValUInt <$> (M.try uInteger <|> M.try hexInteger <|> octInteger)
    | ptc == 4
    = TMValInt <$> signedInteger
    | ptc == 5
    = TMValDouble <$> double
    | ptc == 6 && pfc > 0
    = TMValUInt <$> (M.try uInteger <|> M.try hexInteger <|> octInteger)
    | ptc == 7 && pfc == 0
    = TMValOctet . strToByteString <$> many hexDigitChar
    | ptc == 7
    = TMValOctet . strToByteString <$> count (2 * pfc) hexDigitChar
    | ptc == 8 && pfc == 0
    = TMValString . Data.Text.Short.fromText <$> takeRest
    | ptc == 8
    = TMValString . Data.Text.Short.fromText . T.take pfc <$> takeRest
    | ptc == 9 || ptc == 10
    = TMValTime <$> sunTimeParser
    | ptc == 11 || ptc == 13
    = pure nullValueSimple
    | otherwise
    = fancyFailure
        .  S.singleton
        .  ErrorFail
        $  "Illegal type for TMValue (PTC="
        <> show ptc
        <> ", PFC="
        <> show pfc
        <> ")"


{-# INLINABLE strToByteString #-}
strToByteString :: [Char] -> ByteString
strToByteString ls' =
    let ls = chunks 2 $ if odd (length ls') then '0' : ls' else ls'
    in  B.pack . map (fst . head . readHex) $ ls



-- ptcPfcToParamType (PTC 11) (PFC 0) _ = Right $ ParamDeduced Nothing
-- ptcPfcToParamType (PTC 11) (PFC x) _ = Right $ ParamDeduced (Just x)
-- ptcPfcToParamType (PTC 13) (PFC 0) _ = Right $ ParamSavedSynthetic
-- ptcPfcToParamType ptc pfc _ =
--     Left $ "Unsupported: " <> textDisplay ptc <> " " <> textDisplay pfc


-- | The value, containing also a validity.
data TMValue = TMValue
    { _tmvalValue    :: !TMValueSimple
    , _tmvalValidity :: !Validity
    }
    deriving (Eq, Show, Generic)
makeLenses ''TMValue

instance NFData TMValue
instance Serialise TMValue
instance FromJSON TMValue
instance ToJSON TMValue where
    toEncoding = genericToEncoding defaultOptions


instance ToDouble TMValue where
    {-# INLINABLE toDouble #-}
    toDouble TMValue { _tmvalValue = (TMValInt x) }    = fromIntegral x
    toDouble TMValue { _tmvalValue = (TMValUInt x) }   = fromIntegral x
    toDouble TMValue { _tmvalValue = (TMValDouble x) } = x
    toDouble TMValue { _tmvalValue = (TMValTime x) }   = toDouble x
    toDouble TMValue { _tmvalValue = (TMValString _) } = 0
    toDouble TMValue { _tmvalValue = (TMValOctet _) }  = 0
    toDouble TMValue { _tmvalValue = TMValNothing }    = 0

instance Display TMValue where
    display (TMValue val _) = display val


-- | a null value
{-# INLINABLE nullValue #-}
nullValue :: TMValue
nullValue = TMValue nullValueSimple clearValidity

-- | Returns, if a vlaue is a numeric value
{-# INLINABLE isNumeric #-}
isNumeric :: TMValue -> Bool
isNumeric (TMValue (TMValInt    _) _) = True
isNumeric (TMValue (TMValUInt   _) _) = True
isNumeric (TMValue (TMValDouble _) _) = True
isNumeric _                           = False


{-# INLINABLE getInt #-}
getInt :: Integral a => TMValue -> Maybe a
getInt (TMValue (TMValInt    x) _) = Just $ fromIntegral x
getInt (TMValue (TMValUInt   x) _) = Just $ fromIntegral x
getInt (TMValue (TMValDouble x) _) = Just $ truncate x
getInt _                           = Nothing

{-# INLINABLE getDouble #-}
getDouble :: TMValue -> Maybe Double
getDouble (TMValue (TMValInt    x) _) = Just $ fromIntegral x
getDouble (TMValue (TMValUInt   x) _) = Just $ fromIntegral x
getDouble (TMValue (TMValDouble x) _) = Just x
getDouble _                           = Nothing


-- | Returns, if a value is valid
{-# INLINABLE isValid #-}
isValid :: TMValue -> Bool
isValid x = Data.TM.Validity.isValid $ _tmvalValidity x

-- | Set a validity by using one of the setter functions of the
-- 'Validity' type
{-# INLINABLE setValidity #-}
setValidity :: TMValue -> (Validity -> Validity) -> TMValue
setValidity (TMValue val validity) f = TMValue val (f validity)




-- instance Eq TMIntValue where
--   TMInt  x == TMInt  y = x == y
--   TMUInt x == TMUInt y = x == y
--   TMInt  x == TMUInt y = (x >= 0) && (fromIntegral x == y)
--   TMUInt x == TMInt  y = (y >= 0) && (fromIntegral y == x)


-- instance Ord TMIntValue where
--   compare (TMInt  x) (TMInt  y) = compare x y
--   compare (TMUInt x) (TMUInt y) = compare x y
--   compare (TMInt x) (TMUInt y) =
--     if x < 0 then LT else compare (fromIntegral x) y
--   compare (TMUInt x) (TMInt y) =
--     if y < 0 then GT else compare x (fromIntegral y)







