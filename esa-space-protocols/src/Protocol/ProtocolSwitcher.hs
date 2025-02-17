module Protocol.ProtocolSwitcher
    ( InterfaceSwitcherMap
    , QueueMsg(..)
    , ProtocolQueue
    , CLTUQueue
    , FrameQueue
    , switchProtocolPktC
    , switchProtocolFrameC
    , switchProtocolCltuC
    , receivePktChannelC
    , receiveFrameChannelC
    , receiveCltuChannelC
    , receiveQueueMsg
    , createInterfaceChannel
    ) where


import           RIO
import qualified RIO.HashMap                   as HM

import           Conduit                       as C
import           Conduit.Extras

import           Data.PUS.PUSPacketEncoder
import           Data.PUS.TCRequest

import           Data.PUS.CLTU                  ( EncodedCLTU(cltuRequest) )
import           Data.PUS.TCFrameTypes          ( EncodedTCFrame
                                                , encTcFrameRequest
                                                )

import           Protocol.ProtocolInterfaces    ( ProtocolDestination
                                                    ( destination
                                                    )
                                                , ProtocolInterface
                                                )



-- | The EDEN queue for the given interfaces can encode different protocol levels, 
-- therefore this sum type allows to specify the final content of the EDEN message to be
-- sent.
data QueueMsg =
  EQPacket EncodedPUSPacket
  | EQFrame EncodedTCFrame
  | EQCLTU EncodedCLTU

-- | The type of the queue used to forward TCs to the correct interfaces with the 
-- intended interface.
type ProtocolQueue = TBQueue QueueMsg


-- | The type of the queue used to forward encoded PUS packets for encoding into 
-- TC Frames
type FrameQueue = TBQueue EncodedPUSPacket

-- | The type of the queue used to forward encoded TC frames for encoding into 
-- CLTUs
type CLTUQueue = TBQueue EncodedTCFrame

-- | A HashMap containing the channels where the messages should be sent for EDEN. 
type InterfaceSwitcherMap = HashMap ProtocolInterface ProtocolQueue


-- | The queueSize for the used 'TBQueue'. Defaults to 500
queueSize :: Natural
queueSize = 500


-- | Creates a new 'ProtocolQueue', inserts it into a given 'InterfaceSwitcherMap' and 
-- returns both. Needed for the thread creation of the interfaces. 
createInterfaceChannel
    :: (MonadIO m)
    => InterfaceSwitcherMap
    -> ProtocolInterface
    -> m (ProtocolQueue, InterfaceSwitcherMap)
createInterfaceChannel sm interf = do
    q <- newTBQueueIO queueSize
    return (q, HM.insert interf q sm)


-- | This is an endpoint conduit which forwards an encoded packet ('EncodedPUSPacket')
-- to the right channel for further processing
switchProtocolPktC
    :: (MonadIO m, MonadReader env m, HasLogFunc env)
    => InterfaceSwitcherMap
    -> ConduitT EncodedPUSPacket EncodedPUSPacket m ()
switchProtocolPktC sm = awaitForever $ \pkt -> do
    case pkt ^. encPktRequest . tcReqPayload of
        tc@TCCommand{} -> switchCommand pkt tc
        TCDir{}        -> do
          -- TC Directives work an TC Frame level, so the only available options are 
          -- sending as TC Frames or CLTUs. Therefore, we forward the encoding down to 
          -- the frame level
            yield pkt
        TCScoeCommand{} -> genSwitchCommand pkt

  where
    -- currently, we assume that NCTRS only encodes CLTUs. As Frames and Packets 
    -- are also supported by the NCTRS protocol, this must be changed here for 
    -- the routing to the correct TBQueue
    switchCommand pkt TCCommand { _tcDestination = DestNctrs _ } = yield pkt
    -- in case of an EDEN protocol, but frame format, first delegate to encode into 
    -- TC Frames before sending to the EDEN interface 
    switchCommand pkt TCCommand { _tcDestination = DestEden _ (Space ProtLevelFrame) }
        = yield pkt
    -- in case of an EDEN protocol, but CLTU format, first delegate to encode into 
    -- TC Frames and then CLTUs before sending to the EDEN interface 
    switchCommand pkt TCCommand { _tcDestination = DestEden _ (Space ProtLevelCltu) }
        = yield pkt
    -- NDIU also supports Frames and also CLTU. Currently, only TC Frames are supported 
    -- within AURIS 
    switchCommand pkt TCCommand { _tcDestination = DestNdiu _ } = yield pkt
    -- in all other cases, just forward the packet to the correct interface in packet
    -- format
    switchCommand pkt _ = genSwitchCommand pkt

    genSwitchCommand pkt = do
        let dest = destination (pkt ^. encPktRequest)
        case HM.lookup dest sm of
            Just entry -> atomically $ writeTBQueue entry (EQPacket pkt)
            Nothing ->
                logError
                    $ "ProtocolSwitcher: could not find interface specified in command: "
                    <> displayShow dest



-- | This is an endpoint conduit which forwards an encoded frame ('EncodedTCFrame')
-- to the right channel for further processing
switchProtocolFrameC
    :: (MonadIO m, MonadReader env m, HasLogFunc env)
    => InterfaceSwitcherMap
    -> ConduitT EncodedTCFrame EncodedTCFrame m ()
switchProtocolFrameC sm = awaitForever $ \frame -> do
    case frame ^. encTcFrameRequest . tcReqPayload of
        tc@TCCommand{}  -> switchCommand frame tc
        dir@TCDir{}     -> switchDirective frame dir
        -- SCOE commands cannot be sent as Frames and should already
        -- have been sent to other routes. Therefore, we remote it 
        TCScoeCommand{} -> return ()

  where
    -- in case of EDEN protocol usage with TC Frames, forward to the EDEN interface
    switchCommand frame TCCommand { _tcDestination = DestEden dest (Space ProtLevelFrame) }
        = sendFrameToIF dest frame

    -- in case of NDIU Lite protocol usage with TC Frames, forward to the correct interface 
    switchCommand frame TCCommand { _tcDestination = DestNdiu dest } =
        sendFrameToIF dest frame

    -- in all other cases, forward to the CLTU processing
    switchCommand frame _ = yield frame

    -- in case of EDEN protocol usage with TC Frames, forward to the EDEN interface
    switchDirective frame TCDir { _tcDirDestination = DirDestEden dest DirProtLevelFrame }
        = do
            sendFrameToIF dest frame

    -- in case of NDIU Lite protocol usage with TC Frames, forward to the NDIU interface
    switchDirective frame TCDir { _tcDirDestination = DirDestNdiu dest } = do
        sendFrameToIF dest frame

    switchDirective frame _ = yield frame

    sendFrameToIF dest frame = case HM.lookup dest sm of
        Just entry -> atomically $ writeTBQueue entry (EQFrame frame)
        Nothing ->
            logError
                $ "ProtocolSwitcher: could not find interface specified in command: "
                <> displayShow dest




-- | This is an endpoint conduit which forwards an encoded CLTU ('EncodedCLTU')
-- to the right channel for further processing
switchProtocolCltuC
    :: (MonadIO m, MonadReader env m, HasLogFunc env)
    => InterfaceSwitcherMap
    -> ConduitT EncodedCLTU Void m ()
switchProtocolCltuC sm = awaitForever $ \cltu -> do
    let dest = destination (cltuRequest cltu)
    case HM.lookup dest sm of
        Just entry -> atomically $ writeTBQueue entry (EQCLTU cltu)
        Nothing ->
            logError
                $ "ProtocolSwitcher: could not find interface specified in command: "
                <> displayShow dest


-- | Conduit which receives a 'QueueMsg' via a STM 'TBQueue' and forwards 'EncodePUSPacket's.
-- Other types are discarded. 
receivePktChannelC
    :: (MonadIO m) => ProtocolQueue -> ConduitT () EncodedPUSPacket m ()
receivePktChannelC queue = queueSource queue .| unwrap
  where
    unwrap = awaitForever $ \case
        EQPacket pkt -> yield pkt
        EQFrame  _   -> return ()
        EQCLTU   _   -> return ()

-- | Conduit which receives a 'QueueMsg' via a STM 'TBQueue' and forwards 'EncodedTCFrame's.
-- Other types are discarded. 
receiveFrameChannelC
    :: (MonadIO m) => ProtocolQueue -> ConduitT () EncodedTCFrame m ()
receiveFrameChannelC queue = queueSource queue .| unwrap
  where
    unwrap = awaitForever $ \case
        EQPacket _     -> return ()
        EQFrame  frame -> yield frame
        EQCLTU   _     -> return ()

-- | Conduit which receives a 'QueueMsg' via a STM 'TBQueue' and forwards 'EncodedCLTU's.
-- Other types are discarded. 
receiveCltuChannelC
    :: (MonadIO m) => ProtocolQueue -> ConduitT () EncodedCLTU m ()
receiveCltuChannelC queue = queueSource queue .| unwrap
  where
    unwrap = awaitForever $ \case
        EQPacket _    -> return ()
        EQFrame  _    -> return ()
        EQCLTU   cltu -> yield cltu

-- | Conduit which receives a 'QueueMsg' via a STM 'TBQueue' and simply yields it.
receiveQueueMsg :: (MonadIO m) => ProtocolQueue -> ConduitT () QueueMsg m ()
receiveQueueMsg = queueSource
