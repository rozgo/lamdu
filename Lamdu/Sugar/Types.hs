{-# LANGUAGE NoImplicitPrelude, KindSignatures, TemplateHaskell, DeriveFunctor, DeriveFoldable, DeriveTraversable, GeneralizedNewtypeDeriving, RankNTypes, RecordWildCards #-}
module Lamdu.Sugar.Types
    ( EntityId
    , Definition(..), drEntityId, drName, drBody
    , DefinitionBody(..), _DefinitionBodyExpression, _DefinitionBodyBuiltin
    , ListItemActions(..), itemAddNext, itemDelete
    , VarToTags(..), TagsToVar(..)
    , ParamDelResult(..), ParamAddResult(..)
    , FuncParamActions(..), fpAddNext, fpDelete
    , DefinitionExpression(..), deContent, deTypeInfo
    , AcceptNewType(..)
    , DefinitionTypeInfo(..)
        , _DefinitionExportedTypeInfo
        , _DefinitionNewType
    , Anchors.PresentationMode(..)
    , BinderActions(..), baAddFirstParam
    , NullParamActions(..), npDeleteLambda
    , BinderParams(..)
        , _BinderWithoutParams, _NullParam, _VarParam , _FieldParams
    , BinderParamScopeId(..), bParamScopeId
    , BinderBodyActions(..), bbaAddOuterLet
    , BinderBody(..), bbMActions, bbContent
    , BinderContent(..), _BinderLet, _BinderExpr
    , BinderBodyScope(..)
    , Binder(..)
        , bMPresentationModeProp, bMChosenScopeProp, bParams, bBody
        , bMActions, bBodyScopes
    , DefinitionBuiltin(..), biType, biName, biSetName
    , WrapAction(..), _WrapperAlready, _WrappedAlready, _WrapNotAllowed, _WrapAction
    , SetToHole(..), _SetToHole, _SetWrapperToHole, _AlreadyAHole
    , SetToInnerExpr(..), _SetToInnerExpr, _NoInnerExpr
    , ExtractToDestination(..)
    , Actions(..)
        , wrap, setToHole, setToInnerExpr, extract
    , Body(..)
        , _BodyLam, _BodyApply, _BodyGetVar, _BodyGetField, _BodyInject, _BodyHole
        , _BodyLiteralNum, _BodyLiteralBytes, _BodyLiteralText, _BodyList, _BodyCase, _BodyRecord
        , _BodyFromNom, _BodyToNom
    , EvaluationResult
    , Annotation(..), aInferredType, aMEvaluationResult
    , Payload(..), plEntityId, plAnnotation, plActions, plData
    , Expression(..), rBody, rPayload
    , DefinitionU
    , LetFloatResult(..)
    , LetActions(..)
        , laSetToInner, laSetToHole, laFloat
    , Let(..)
        , lEntityId, lValue, lName, lUsages
        , lActions, lAnnotation, lBodyScope, lBody
    , ListItem(..), liMActions, liExpr
    , ListActions(..)
    , List(..), lValues, lMActions, lNilEntityId
    -- record:
    , RecordField(..), rfMDelete, rfTag, rfExpr
    , RecordTail(..), _RecordExtending, _ClosedRecord
    , RecordAddFieldResult(..), rafrNewTag, rafrNewVal, rafrRecExtend
    , Record(..), rItems, rMAddField, rTail
    -- case
    , CaseAlt(..), caMDelete, caTag, caHandler
    , CaseTail(..), _CaseExtending, _ClosedCase
    , CaseAddAltResult(..), caarNewTag, caarNewVal, caarCase
    , CaseArg(..), caVal, caMToLambdaCase
    , CaseKind(..), _LambdaCase, _CaseWithArg
    , Case(..), cKind, cAlts, cMAddAlt, cTail, cEntityId
    , Nominal(..), nTId, nVal
    --
    , GetField(..), gfRecord, gfTag
    , Inject(..), iTag, iMVal
    , ParameterForm(..), _GetFieldParameter, _GetParameter
    , NameRef(..), nrName, nrGotoDefinition
    , Param(..), pNameRef, pForm, pBinderMode
    , BinderVarForm(..), _GetDefinition, _GetLet
    , BinderVarInline(..), _InlineVar, _CannotInlineDueToUses, _CannotInline
    , BinderVar(..), bvNameRef, bvForm, bvInline
    , GetVar(..), _GetParam, _GetParamsRecord, _GetBinder
    , ParamsRecordVar(..), prvFieldNames
    , SpecialArgs(..), _NoSpecialArgs, _ObjectArg, _InfixArgs
    , AnnotatedArg(..), aaTag, aaExpr
    , Apply(..), aFunc, aSpecialArgs, aAnnotatedArgs
    , NamedParamInfo(..), npiName, npiMActions
    , NullParamInfo(..), nullParamInfoMActions
    , FuncParam(..), fpId, fpInfo, fpAnnotation, fpHiddenIds
    , Unwrap(..), _UnwrapMAction, _UnwrapTypeMismatch
    , HoleArg(..), haExpr, haUnwrap
    , HoleOption(..), hoVal, hoSugaredBaseExpr, hoResults
    , HoleActions(..), holeGuid, holeOptions, holeOptionLiteralNum, holeOptionLiteralBytes
      , holeOptionLiteralText
    , Hole(..), holeMActions, holeMArg
    , ScopeGetVar(..), sgvGetVar, sgvVal
    , TIdG(..), tidgName, tidgTId
    , HoleResultScore
    , HoleResult(..)
        , holeResultConverted
        , holeResultPick
    , IsInjected(..)
    , PickedResult(..), prIdTranslation
    , TagG(..), tagGName, tagVal, tagInstance
    , Lambda(..), lamBinder, lamMode
    , BinderMode(..)
    ) where

import           Prelude.Compat

import qualified Control.Lens as Lens
import           Control.Monad.ListT (ListT)
import qualified Data.ByteString as SBS
import           Data.CurAndPrev (CurAndPrev)
import qualified Data.List as List
import           Data.Map (Map)
import           Data.Store.Guid (Guid)
import           Data.Store.Transaction (Transaction, MkProperty)
import           Lamdu.Data.Anchors (BinderParamScopeId(..), bParamScopeId)
import qualified Lamdu.Data.Anchors as Anchors
import qualified Lamdu.Data.Definition as Definition
import qualified Lamdu.Eval.Val as E
import           Lamdu.Expr.Scheme (Scheme)
import           Lamdu.Expr.Type (Type)
import qualified Lamdu.Expr.Type as T
import qualified Lamdu.Expr.Val as V
import           Lamdu.Sugar.Internal.EntityId (EntityId)

type T = Transaction

data WrapAction m
    = WrapperAlready (Guid, EntityId) -- I'm an apply-of-hole, (Guid,EntityId of hole), no need to wrap
    | WrappedAlready (Guid, EntityId) -- I'm an arg of apply-of-hole (Guid,EntityId of hole), no need to wrap
    | WrapNotAllowed -- I'm a hole
    | WrapAction (T m (Guid, EntityId)) -- Wrap me!

data SetToHole m
    = SetToHole (T m (Guid, EntityId))
    | SetWrapperToHole (T m (Guid, EntityId))
    | AlreadyAHole
    | AlreadyAppliedToHole

data SetToInnerExpr m
    = SetToInnerExpr (T m EntityId)
    | NoInnerExpr

data ExtractToDestination
    = ExtractToLet EntityId
    | ExtractToDef EntityId

data Actions m = Actions
    { _wrap :: WrapAction m
    , _setToHole :: SetToHole m
    , _setToInnerExpr :: SetToInnerExpr m
    , _extract :: T m ExtractToDestination
    }

type EvaluationResult = Map E.ScopeId (E.EvalResult ())

data Annotation = Annotation
    { _aInferredType :: Type
    , _aMEvaluationResult :: CurAndPrev (Maybe EvaluationResult)
    } deriving (Show)

data Payload m a = Payload
    { _plAnnotation :: Annotation
    , _plActions :: Maybe (Actions m)
    , _plEntityId :: EntityId
    , _plData :: a
    } deriving (Functor, Foldable, Traversable)

data Expression name m a = Expression
    { _rBody :: Body name m (Expression name m a)
    , _rPayload :: Payload m a
    } deriving (Functor, Foldable, Traversable)

data ListItemActions m = ListItemActions
    { _itemAddNext :: T m EntityId
    , _itemDelete :: T m ()
    }

data VarToTags = VarToTags
    { vttReplacedVar :: V.Var
    , vttReplacedVarEntityId :: EntityId
      -- Since this is just a result of a transaction, no name is
      -- actually needed in the Tags below
    , vttReplacedByTag :: TagG ()
    , vttNewTag :: TagG ()
    }

data ParamAddResult
    = ParamAddResultNewVar EntityId V.Var
    | ParamAddResultVarToTags VarToTags
    | ParamAddResultNewTag (TagG ())

data TagsToVar = TagsToVar
    { ttvReplacedTag :: TagG ()
    , ttvReplacedByVar :: V.Var
    , ttvReplacedByVarEntityId :: EntityId
    , ttvDeletedTag :: TagG ()
    }

data ParamDelResult
    = ParamDelResultDelVar
    | ParamDelResultTagsToVar TagsToVar
    | ParamDelResultDelTag

data FuncParamActions m = FuncParamActions
    { _fpAddNext :: T m ParamAddResult
    , _fpDelete :: T m ParamDelResult
    }

data NamedParamInfo name m = NamedParamInfo
    { _npiName :: name
    , _npiMActions :: Maybe (FuncParamActions m)
    }

newtype NullParamActions m = NullParamActions
    { _npDeleteLambda :: T m ()
    }

data NullParamInfo m = NullParamInfo
    { _nullParamInfoMActions :: Maybe (NullParamActions m)
    }

data FuncParam info = FuncParam
    { _fpId :: EntityId
    , _fpAnnotation :: Annotation
    , _fpInfo :: info
    , -- Sometimes the Lambda disappears in Sugar, the Param "swallows" its id
      _fpHiddenIds :: [EntityId]
    } deriving (Functor, Foldable, Traversable)

data TagG name = TagG
    { _tagInstance :: EntityId -- Unique across different uses of a tag
    , _tagVal :: T.Tag
    , _tagGName :: name
    }

newtype PickedResult = PickedResult
    { _prIdTranslation :: [(EntityId, EntityId)]
    }

data IsInjected = Injected | NotInjected

instance Monoid IsInjected where
    mempty = NotInjected
    mappend NotInjected NotInjected = NotInjected
    mappend _ _ = Injected

type HoleResultScore = [Int]

data HoleResult name m = HoleResult
    { _holeResultConverted :: Expression name m IsInjected
    , _holeResultPick :: T m PickedResult
    }

data ScopeGetVar name m = ScopeGetVar
    { _sgvGetVar :: GetVar name m
    , _sgvVal :: V.Val ()
    }

data TIdG name = TIdG
    { _tidgName :: name
    , _tidgTId :: T.NominalId
    }

data HoleOption name m = HoleOption
    { _hoVal :: V.Val ()
    , _hoSugaredBaseExpr :: T m (Expression name m ())
    , -- A group in the hole results based on this option
      _hoResults :: ListT (T m) (HoleResultScore, T m (HoleResult name m))
    }

data HoleActions name m = HoleActions
    { _holeGuid :: Guid -- TODO: Replace this with a way to associate data?
    , _holeOptions :: T m [HoleOption name m]
    , _holeOptionLiteralNum :: Double -> T m (HoleOption name m)
    , _holeOptionLiteralBytes :: SBS.ByteString -> T m (HoleOption name m)
    , _holeOptionLiteralText :: String -> T m (HoleOption name m)
    }

data Unwrap m
    = UnwrapMAction (Maybe (T m EntityId))
    | UnwrapTypeMismatch

data HoleArg m expr = HoleArg
    { _haExpr :: expr
    , _haUnwrap :: Unwrap m
    } deriving (Functor, Foldable, Traversable)

data Hole name m expr = Hole
    { _holeMActions :: Maybe (HoleActions name m)
    , _holeMArg :: Maybe (HoleArg m expr)
    } deriving (Functor, Foldable, Traversable)

data ListItem m expr = ListItem
    { _liMActions :: Maybe (ListItemActions m)
    , _liExpr :: expr
    } deriving (Functor, Foldable, Traversable)

data ListActions m = ListActions
    { addFirstItem :: T m EntityId
    , replaceNil :: T m EntityId
    }

data List m expr = List
    { _lValues :: [ListItem m expr]
    , _lMActions :: Maybe (ListActions m)
    , -- Nil EntityId stays consistent when adding items.
        -- (Exposed for consistent animations)
        _lNilEntityId :: EntityId
    } deriving (Functor, Foldable, Traversable)

{- Record start -}
data RecordField name m expr = RecordField
    { _rfMDelete :: Maybe (T m EntityId)
    , _rfTag :: TagG name
    , _rfExpr :: expr -- field type or val
    } deriving (Functor, Foldable, Traversable)

data RecordTail m expr
    = RecordExtending expr
    | ClosedRecord (Maybe (T m EntityId)) -- delete action
    deriving (Functor, Foldable, Traversable)

data RecordAddFieldResult = RecordAddFieldResult
    { _rafrNewTag :: TagG ()
    , _rafrNewVal :: EntityId
    , _rafrRecExtend :: EntityId
    }

data Record name m expr = Record
    { _rItems :: [RecordField name m expr]
    , _rTail :: RecordTail m expr
    , _rMAddField :: Maybe (T m RecordAddFieldResult)
    } deriving (Functor, Foldable, Traversable)
{- Record end -}

{- Case start -}
data CaseAlt name m expr = CaseAlt
    { _caMDelete :: Maybe (T m EntityId)
    , _caTag :: TagG name
    , _caHandler :: expr
    } deriving (Functor, Foldable, Traversable)

data CaseTail m expr
    = CaseExtending expr
    | ClosedCase (Maybe (T m EntityId)) -- delete action
    deriving (Functor, Foldable, Traversable)

data CaseAddAltResult = CaseAddAltResult
    { _caarNewTag :: TagG ()
    , _caarNewVal :: EntityId
    , _caarCase :: EntityId
    }

data CaseArg m expr = CaseArg
    { _caVal :: expr
    , _caMToLambdaCase :: Maybe (T m EntityId)
    } deriving (Functor, Foldable, Traversable)

data CaseKind m expr
    = LambdaCase
    | CaseWithArg (CaseArg m expr)
    deriving (Functor, Foldable, Traversable)

data Case name m expr = Case
    { _cKind :: CaseKind m expr
    , _cAlts :: [CaseAlt name m expr]
    , _cTail :: CaseTail m expr
    , _cMAddAlt :: Maybe (T m CaseAddAltResult)
    , -- The entity id of the underlying lambda-case
      _cEntityId :: EntityId
    } deriving (Functor, Foldable, Traversable)
{- Case end -}

data GetField name expr = GetField
    { _gfRecord :: expr
    , _gfTag :: TagG name
    } deriving (Functor, Foldable, Traversable)

data Inject name expr = Inject
    { _iTag :: TagG name
    , _iMVal :: Maybe expr
    } deriving (Functor, Foldable, Traversable)

data NameRef name m = NameRef
    { _nrName :: name
    , _nrGotoDefinition :: T m EntityId
    }

data ParameterForm = GetFieldParameter | GetParameter
    deriving (Eq, Ord)

data BinderMode = NormalBinder | LightLambda

data Param name m = Param
    { _pNameRef :: NameRef name m
    , _pForm :: ParameterForm
    , _pBinderMode :: BinderMode
    }

data BinderVarForm = GetDefinition | GetLet
    deriving (Eq, Ord)

data BinderVarInline m
    = InlineVar (T m EntityId)
    | CannotInlineDueToUses [EntityId]
    | CannotInline

data BinderVar name m = BinderVar
    { _bvNameRef :: NameRef name m
    , _bvForm :: BinderVarForm
    , -- Just means it is stored and inlinable:
      _bvInline :: BinderVarInline m
    }

newtype ParamsRecordVar name = ParamsRecordVar
    { _prvFieldNames :: [name]
    } deriving (Eq, Ord, Functor, Foldable, Traversable)

data GetVar name m
    = GetParam (Param name m)
    | GetParamsRecord (ParamsRecordVar name)
    | GetBinder (BinderVar name m)

data SpecialArgs expr
    = NoSpecialArgs
    | ObjectArg expr
    | InfixArgs Int expr expr
    deriving (Functor, Foldable, Traversable)

data AnnotatedArg name expr = AnnotatedArg
    { _aaTag :: TagG name
    , _aaExpr :: expr
    } deriving (Functor, Foldable, Traversable)

data Apply name expr = Apply
    { _aFunc :: expr
    , _aSpecialArgs :: SpecialArgs expr
    , _aAnnotatedArgs :: [AnnotatedArg name expr]
    } deriving (Functor, Foldable, Traversable)

data Nominal name expr = Nominal
    { _nTId :: TIdG name
    , _nVal :: expr
    } deriving (Functor, Foldable, Traversable)

data Lambda name m expr = Lambda
    { _lamMode :: BinderMode
    , _lamBinder :: Binder name m expr
    } deriving (Functor, Foldable, Traversable)

data Body name m expr
    = BodyLam (Lambda name m expr)
    | BodyApply (Apply name expr)
    | BodyHole (Hole name m expr)
    | BodyLiteralNum Double
    | BodyLiteralBytes SBS.ByteString
    | BodyLiteralText String
    | BodyList (List m expr)
    | BodyRecord (Record name m expr)
    | BodyGetField (GetField name expr)
    | BodyCase (Case name m expr)
    | BodyInject (Inject name expr)
    | BodyGetVar (GetVar name m)
    | BodyToNom (Nominal name expr)
    | BodyFromNom (Nominal name expr)
    deriving (Functor, Foldable, Traversable)

instance Show name => Show (NamedParamInfo name m) where
    show NamedParamInfo{..} =
        "(NamedParamInfo " ++ show _npiName ++ ")"

instance Show info => Show (FuncParam info) where
    show FuncParam{..} = "(FuncParam " ++ show _fpId ++ " " ++ show _fpInfo ++
                                              " " ++ show _fpAnnotation ++ " )"


instance Show expr => Show (Body name m expr) where
    show (BodyLam _) = "TODO show lam"
    show BodyHole {} = "Hole"
    show (BodyLiteralNum i) = show i
    show (BodyLiteralBytes i) = show i
    show (BodyLiteralText i) = show i
    show (BodyList (List items _ _)) =
        concat
        [ "["
        , List.intercalate ", " $ map (show . _liExpr) items
        , "]"
        ]
    show BodyApply {} = "LabelledApply:TODO"
    show BodyRecord {} = "Record:TODO"
    show BodyGetField {} = "GetField:TODO"
    show BodyCase {} = "Case:TODO"
    show BodyInject {} = "Inject:TODO"
    show BodyGetVar {} = "GetVar:TODO"
    show BodyFromNom {} = "FromNom:TODO"
    show BodyToNom {} = "ToNom:TODO"

data LetFloatResult = LetFloatResult
    { lfrNewEntity :: EntityId
    , lfrMVarToTags :: Maybe VarToTags
    }

data LetActions m = LetActions
    { _laSetToInner :: T m ()
    , _laSetToHole :: T m EntityId
    , _laFloat :: T m LetFloatResult
    }

data Let name m expr = Let
    { _lValue :: Binder name m expr -- "let [[foo = bar]] in x"
    , _lEntityId :: EntityId
    , _lUsages :: [EntityId]
    , _lAnnotation :: Annotation
    , _lName :: name
    , _lActions :: Maybe (LetActions m)
    , -- This is a mapping from parent scope (the ScopeId inside
      -- BinderParamScopeId for outer-most let) to the inside of the
      -- redex lambda (redex is applied exactly once):
      _lBodyScope :: CurAndPrev (Map E.ScopeId E.ScopeId)
    , _lBody :: BinderBody name m expr -- "let foo = bar in [[x]]"
    } deriving (Functor, Foldable, Traversable)

newtype BinderActions m = BinderActions
    { _baAddFirstParam :: T m ParamAddResult
    }

data BinderParams name m
    = -- a definition or let-item without parameters
      BinderWithoutParams
    | -- null param represents a lambda whose parameter's type is inferred
      -- to be the empty record.
      -- This is often used to represent "deferred execution"
      NullParam (FuncParam (NullParamInfo m))
    | VarParam (FuncParam (NamedParamInfo name m))
    | FieldParams [(T.Tag, FuncParam (NamedParamInfo name m))]

data BinderContent name m expr
    = BinderLet (Let name m expr)
    | BinderExpr expr
    deriving (Functor, Foldable, Traversable)

newtype BinderBodyActions m = BinderBodyActions
    { _bbaAddOuterLet :: T m EntityId
    }

data BinderBody name m expr = BinderBody
    { _bbMActions :: Maybe (BinderBodyActions m)
    , _bbContent :: BinderContent name m expr
    } deriving (Functor, Foldable, Traversable)

data BinderBodyScope
    = SameAsParentScope
      -- ^ no binder params
    | BinderBodyScope (CurAndPrev (Map E.ScopeId [BinderParamScopeId]))
      -- ^ binder has params, use the map to get the param application
      -- scopes

data Binder name m expr = Binder
    { _bMPresentationModeProp :: Maybe (MkProperty m Anchors.PresentationMode)
    , _bMChosenScopeProp :: Maybe (MkProperty m (Maybe BinderParamScopeId))
    , _bParams :: BinderParams name m
    , _bBody :: BinderBody name m expr
    , _bMActions :: Maybe (BinderActions m)
    , -- The scope inside a lambda (if exists)
      _bBodyScopes :: BinderBodyScope
    } deriving (Functor, Foldable, Traversable)

data AcceptNewType m = AcceptNewType
    { antOldExportedType :: Definition.ExportedType
    , antNewInferredType :: Scheme
    , antAccept :: T m ()
    }

data DefinitionTypeInfo m
    = DefinitionExportedTypeInfo Scheme
    | DefinitionNewType (AcceptNewType m)

data DefinitionExpression name m expr = DefinitionExpression
    { _deTypeInfo :: DefinitionTypeInfo m
    , _deContent :: Binder name m expr
    } deriving (Functor, Foldable, Traversable)

data DefinitionBuiltin m = DefinitionBuiltin
    { _biName :: Definition.FFIName
    , _biSetName :: Definition.FFIName -> T m ()
    , _biType :: Scheme
    }

data DefinitionBody name m expr
    = DefinitionBodyExpression (DefinitionExpression name m expr)
    | DefinitionBodyBuiltin (DefinitionBuiltin m)
    deriving (Functor, Foldable, Traversable)

data Definition name m expr = Definition
    { _drName :: name
    , _drEntityId :: EntityId
    , _drBody :: DefinitionBody name m expr
    } deriving (Functor, Foldable, Traversable)

type DefinitionU m a = Definition Guid m (Expression Guid m a)

Lens.makeLenses ''Actions
Lens.makeLenses ''AnnotatedArg
Lens.makeLenses ''Annotation
Lens.makeLenses ''Apply
Lens.makeLenses ''Binder
Lens.makeLenses ''BinderActions
Lens.makeLenses ''BinderBody
Lens.makeLenses ''BinderBodyActions
Lens.makeLenses ''BinderVar
Lens.makeLenses ''Body
Lens.makeLenses ''Case
Lens.makeLenses ''CaseAddAltResult
Lens.makeLenses ''CaseAlt
Lens.makeLenses ''CaseArg
Lens.makeLenses ''Definition
Lens.makeLenses ''DefinitionBuiltin
Lens.makeLenses ''DefinitionExpression
Lens.makeLenses ''Expression
Lens.makeLenses ''FuncParam
Lens.makeLenses ''FuncParamActions
Lens.makeLenses ''GetField
Lens.makeLenses ''Hole
Lens.makeLenses ''HoleActions
Lens.makeLenses ''HoleArg
Lens.makeLenses ''HoleOption
Lens.makeLenses ''HoleResult
Lens.makeLenses ''Inject
Lens.makeLenses ''Lambda
Lens.makeLenses ''Let
Lens.makeLenses ''LetActions
Lens.makeLenses ''List
Lens.makeLenses ''ListItem
Lens.makeLenses ''ListItemActions
Lens.makeLenses ''NameRef
Lens.makeLenses ''NamedParamInfo
Lens.makeLenses ''Nominal
Lens.makeLenses ''NullParamActions
Lens.makeLenses ''NullParamInfo
Lens.makeLenses ''Param
Lens.makeLenses ''ParamsRecordVar
Lens.makeLenses ''Payload
Lens.makeLenses ''PickedResult
Lens.makeLenses ''Record
Lens.makeLenses ''RecordAddFieldResult
Lens.makeLenses ''RecordField
Lens.makeLenses ''ScopeGetVar
Lens.makeLenses ''TIdG
Lens.makeLenses ''TagG
Lens.makePrisms ''BinderContent
Lens.makePrisms ''BinderParams
Lens.makePrisms ''BinderVarForm
Lens.makePrisms ''BinderVarInline
Lens.makePrisms ''Body
Lens.makePrisms ''CaseKind
Lens.makePrisms ''CaseTail
Lens.makePrisms ''DefinitionBody
Lens.makePrisms ''DefinitionTypeInfo
Lens.makePrisms ''GetVar
Lens.makePrisms ''ParameterForm
Lens.makePrisms ''RecordTail
Lens.makePrisms ''SetToHole
Lens.makePrisms ''SetToInnerExpr
Lens.makePrisms ''SpecialArgs
Lens.makePrisms ''Unwrap
Lens.makePrisms ''WrapAction
