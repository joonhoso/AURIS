{-# LANGUAGE BangPatterns
    , OverloadedStrings #-}
module Data.PUS.CLTU
    (
        CLTU
        , cltuPayLoad
        , encode
        , decode 
    )
where


import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Lazy as B
import Data.ByteString.Builder
import Data.Word
import Data.Int
import Data.Bits
import Data.Text (Text)

import Data.PUS.Config
import Data.PUS.CLTUTable

import qualified TextShow as TS
import TextShow.Data.Integral



-- The CLTU itself
data CLTU = CLTU {
    cltuPayLoad :: ByteString
}


{-# INLINABLE cltuHeader #-}
-- | The CLTU header 0xeb90
cltuHeader :: ByteString
cltuHeader = B.pack [0xeb, 0x90]

-- | The CLTU trailer 
{-# INLINABLE cltuTrailer #-}
cltuTrailer :: Int -> ByteString
cltuTrailer n = B.replicate (fromIntegral n) 0x55

-- | Encodes a CLTU into a ByteString suitable for sending via a transport protocol
-- | Takes a config as some values of the CLTU ecoding can be specified per mission
-- | (e.g. block length of the encoding)
encode :: Config -> CLTU -> ByteString
encode cfg (CLTU pl) = toLazyByteString (mconcat [lazyByteString cltuHeader, encodedFrame, trailer])
    where
        encodedFrame = encodeCodeBlocks cfg pl
        trailer = encodeCodeBlock (cltuTrailer (fromIntegral (cfgCltuBlockSize cfg - 1)))


decode :: Config -> ByteString -> Either Text CLTU
decode cfg pl = 
    if cltuHeader `B.isPrefixOf` pl
        then
            let cbSize = cfgCltuBlockSize cfg
                blocks = chunkedBy (fromIntegral cbSize) (B.drop (B.length cltuHeader) pl)

                proc _ (Left err) = Left err
                proc bs (Right cb) = 
                    case checkCodeBlock cbSize bs of
                        Left err -> Left err
                        Right dataBlock -> Right (dataBlock : cb)
                
                checkedCBs = foldr proc (Right mempty) blocks
            in
            case checkedCBs of
                Left err -> Left err
                Right parts -> Right $ CLTU (toLazyByteString . mconcat . map lazyByteString $ parts)
        else
            Left "CLTU Header is missing"


{-# INLINABLE encodeCodeBlocks #-}
-- | Takes a ByteString as payload, splits it into CLTU code blocks according to 
-- | the configuration, calculates the parity for the code blocks by possibly 
-- | padding the last code block with the trailer and returns a builder
-- | with the result
encodeCodeBlocks :: Config -> ByteString -> Builder
encodeCodeBlocks cfg pl = 
    let cbSize = fromIntegral $ cfgCltuBlockSize cfg - 1
        blocks = chunkedBy cbSize pl
        pad bs = 
            let len = fromIntegral (B.length bs) in
            if len < cbSize then B.append bs (cltuTrailer (cbSize - len)) else bs
    in
    mconcat $ map (encodeCodeBlock . pad) blocks



{-# INLINABLE encodeCodeBlock #-}
-- | encodes a single CLTU code block. This function assumes that the given ByteString
-- | is already in the correct code block length - 1 (1 byte for parity will be added)
encodeCodeBlock :: ByteString -> Builder
encodeCodeBlock block = 
    lazyByteString block <> word8 (cltuParity block)


{-# INLINABLE cltuParity #-}
-- | calculates the parity of a single code block. The code block is assumed to
-- | be of the specified code block length
cltuParity :: ByteString -> Word8 
cltuParity !block =
    let proc :: Word8 -> Int32 -> Int32
        proc !octet !sreg = fromIntegral $ cltuTable (fromIntegral sreg) octet
        sreg1 = B.foldr proc 0 block 
        !result = fromIntegral $ ((sreg1 `xor` 0xFF) `shiftL` 1) .&. 0xFE
    in
    result
        

checkCodeBlock :: Word8 -> ByteString -> Either Text ByteString
checkCodeBlock expectedLen block =
    let len = B.length block
        checkBlock = B.take (len - 1) block
        parity = block `B.index` (len - 1)
        calculatedParity = cltuParity checkBlock
    in
    if fromIntegral expectedLen /= len
        then Left $ TS.toText (TS.fromText "CLTU block does not have the right length, expected: "
            <> TS.showb expectedLen
            <> TS.fromText " received: "
            <> TS.showb len)
        else
            if calculatedParity == parity 
            then Right checkBlock
            else 
                if B.all (== 0x55) checkBlock
                    then Right checkBlock
                    else 
                        Left $ TS.toText (TS.fromText "Error: CLTU code block check failed, calculated: " 
                        <> showbHex calculatedParity 
                        <> TS.fromText " received: " 
                        <> showbHex parity)


-- | Chunk a @bs into list of smaller byte strings of no more than @n elements
chunkedBy :: Int -> ByteString -> [ByteString]
chunkedBy n bs = if B.length bs == 0
  then []
  else case B.splitAt (fromIntegral n) bs of
    (as, zs) -> as : chunkedBy n zs
{-# INLINABLE chunkedBy #-}    


