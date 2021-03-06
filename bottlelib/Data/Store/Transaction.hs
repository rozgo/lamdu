{-# LANGUAGE NoImplicitPrelude, GeneralizedNewtypeDeriving, RankNTypes, TemplateHaskell #-}

module Data.Store.Transaction
    ( Transaction, run
    , Store(..), onStoreM
    , Changes, fork, merge
    , lookupBS, lookup
    , insertBS, insert
    , delete, deleteIRef
    , readIRef, writeIRef
    , isEmpty
    , irefExists
    , newIRef, newKey
    , assocDataRef, assocDataRefDef
    , Property
    , fromIRef
    , MkProperty(..), mkProperty, mkPropertyFromIRef
    , getP, setP, modP
    )
where

import           Control.Applicative ((<|>))
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Lens.Tuple
import           Control.Monad.Trans.Class (MonadTrans(..))
import           Control.Monad.Trans.Reader (ReaderT, runReaderT)
import qualified Control.Monad.Trans.Reader as Reader
import           Control.Monad.Trans.State (StateT, runStateT)
import qualified Control.Monad.Trans.State as State
import           Data.Binary (Binary)
import           Data.Binary.Utils (encodeS, decodeS)
import           Data.ByteString (ByteString)
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Maybe (fromMaybe, isJust)
import           Data.UUID.Types (UUID)
import qualified Data.UUID.Utils as UUIDUtils
import           Data.Store.IRef (IRef)
import qualified Data.Store.IRef as IRef
import qualified Data.Store.Property as Property
import           Data.Store.Rev.Change (Key, Value)

import           Prelude.Compat hiding (lookup)

type ChangesMap = Map Key (Maybe Value)

-- 't' is a phantom-type tag meant to make sure you run Transactions
-- with the right store
data Store m = Store
    { storeNewKey :: m Key
    , storeLookup :: Key -> m (Maybe Value)
    , storeAtomicWrite :: [(Key, Maybe Value)] -> m ()
    }

onStoreM :: (forall a. m a -> n a) -> Store m -> Store n
onStoreM f x = x
    { storeNewKey = f $ storeNewKey x
    , storeLookup = f . storeLookup x
    , storeAtomicWrite = f . storeAtomicWrite x
    }

data Askable m = Askable
    { _aStore :: Store m
    , _aBase :: ChangesMap
    }
Lens.makeLenses ''Askable

-- Define transformer stack:
newtype Transaction m a =
    Transaction (ReaderT (Askable m) (StateT ChangesMap m) a)
    deriving (Functor, Applicative, Monad)
liftAskable :: ReaderT (Askable m) (StateT ChangesMap m) a -> Transaction m a
liftAskable = Transaction
liftChangesMap :: Monad m => StateT ChangesMap m a -> Transaction m a
liftChangesMap = liftAskable . lift
liftInner :: Monad m => m a -> Transaction m a
liftInner = Transaction . lift . lift

getStore :: Monad m => Transaction m (Store m)
getStore = liftAskable $ Reader.asks (Lens.view aStore)

getBase :: Monad m => Transaction m ChangesMap
getBase = liftAskable $ Reader.asks (Lens.view aBase)

run :: Monad m => Store m -> Transaction m a -> m a
run store (Transaction transaction) = do
    (res, changes) <-
        transaction
        & (`runReaderT` Askable store mempty)
        & (`runStateT` mempty)
    storeAtomicWrite store $ Map.toList changes
    return res

newtype Changes = Changes ChangesMap

-- | Fork the given transaction into its own space.  Unless the
-- transaction is later "merged" into the main transaction, its
-- changes will not be committed anywhere.
fork :: Monad m => Transaction m a -> Transaction m (a, Changes)
fork (Transaction discardableTrans) = do
    changes <- liftChangesMap State.get
    -- Map.union is left-biased, so changes correctly override base:
    askable <- liftAskable Reader.ask <&> aBase %~ Map.union changes
    discardableTrans
        & (`runReaderT` askable)
        & (`runStateT` mempty)
        & liftInner
        <&> _2 %~ Changes

merge :: Monad m => Changes -> Transaction m ()
merge (Changes changes) =
    liftChangesMap . State.modify $ Map.union changes

isEmpty :: Monad m => Transaction m Bool
isEmpty = liftChangesMap (State.gets Map.null)

lookupBS :: Monad m => UUID -> Transaction m (Maybe Value)
lookupBS uuid = do
    base <- getBase
    changes <- liftChangesMap State.get
    case Map.lookup uuid changes <|> Map.lookup uuid base of
        Nothing -> do
            store <- getStore
            liftInner $ storeLookup store uuid
        Just res -> return res

insertBS :: Monad m => UUID -> ByteString -> Transaction m ()
insertBS key = liftChangesMap . State.modify . Map.insert key . Just

delete :: Monad m => UUID -> Transaction m ()
delete key = liftChangesMap . State.modify . Map.insert key $ Nothing

lookup :: (Monad m, Binary a) => UUID -> Transaction m (Maybe a)
lookup = (fmap . fmap) decodeS . lookupBS

insert :: (Monad m, Binary a) => UUID -> a -> Transaction m ()
insert key = insertBS key . encodeS

writeUUID :: (Monad m, Binary a) => UUID -> a -> Transaction m ()
writeUUID = insert

uuidExists :: Monad m => UUID -> Transaction m Bool
uuidExists = fmap isJust . lookupBS

readUUIDMb :: (Monad m, Binary a) => Transaction m a -> UUID -> Transaction m a
readUUIDMb nothingCase uuid =
    maybe nothingCase return =<< lookup uuid

readUUID :: (Monad m, Binary a) => UUID -> Transaction m a
readUUID uuid = readUUIDMb failure uuid
    where
        failure = fail $ "Inexistent uuid: " ++ show uuid ++ " referenced"

deleteIRef :: Monad m => IRef m a -> Transaction m ()
deleteIRef = delete . IRef.uuid

readIRef :: (Monad m, Binary a) => IRef m a -> Transaction m a
readIRef = readUUID . IRef.uuid

irefExists :: Monad m => IRef m a -> Transaction m Bool
irefExists = uuidExists . IRef.uuid

writeIRef :: (Monad m, Binary a) => IRef m a -> a -> Transaction m ()
writeIRef = writeUUID . IRef.uuid

newKey :: Monad m => Transaction m Key
newKey = liftInner . storeNewKey =<< getStore

newIRef :: (Monad m, Binary a) => a -> Transaction m (IRef m a)
newIRef val = do
    newUUID <- newKey
    insert newUUID val
    return $ IRef.unsafeFromUUID newUUID

---------- Properties:

type Property m = Property.Property (Transaction m)

fromIRef :: (Monad m, Binary a) => IRef m a -> Transaction m (Property m a)
fromIRef iref = flip Property.Property (writeIRef iref) <$> readIRef iref

newtype MkProperty m a = MkProperty { _mkProperty :: Transaction m (Property m a) }
Lens.makeLenses ''MkProperty

mkPropertyFromIRef :: (Monad m, Binary a) => IRef m a -> MkProperty m a
mkPropertyFromIRef = MkProperty . fromIRef

getP :: Monad m => MkProperty m a -> Transaction m a
getP = fmap Property.value . (^. mkProperty)

setP :: Monad m => MkProperty m a -> a -> Transaction m ()
setP (MkProperty mkProp) val = do
    prop <- mkProp
    Property.set prop val

modP :: Monad m => MkProperty m a -> (a -> a) -> Transaction m ()
modP (MkProperty mkProp) f = do
    prop <- mkProp
    Property.pureModify prop f

assocDataRef :: (Binary a, Monad m) => ByteString -> UUID -> MkProperty m (Maybe a)
assocDataRef str uuid = MkProperty $ do
    val <- lookup assocUUID
    return $ Property.Property val set
    where
        assocUUID = UUIDUtils.augment str uuid
        set Nothing = delete assocUUID
        set (Just x) = writeUUID assocUUID x

assocDataRefDef :: (Eq a, Binary a, Monad m) => a -> ByteString -> UUID -> MkProperty m a
assocDataRefDef def str uuid =
    assocDataRef str uuid
    & mkProperty . Lens.mapped %~ Property.pureCompose (fromMaybe def) f
    where
        f x
            | x == def = Nothing
            | otherwise = Just x
