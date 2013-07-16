{-# LANGUAGE TemplateHaskell #-}
module Lamdu.Data.Infer.Internal
  ( RefVars(..)
  , RefData(..), rdVars, rdBody
  , ExprRefs(..), exprRefsUF, exprRefsData
  , Context(..), ctxExprRefs, ctxDefRefs
  , LoadedDef(..), ldDef, ldType
  , TypedValue(..), tvVal, tvType
  , ScopedTypedValue(..), stvTV, stvScope
  ) where

import Data.Map (Map)
import Data.Set (Set)
import Data.Store.Guid (Guid)
import Data.UnionFind (Ref, RefMap)
import qualified Control.Lens as Lens
import qualified Data.UnionFind as UF
import qualified Lamdu.Data.Expression as Expr

data RefVars = RefVars
  { _rvScopeTypes :: Map Guid Ref -- intersected
  , _rvGetVars :: Set Guid -- unified
  }

data RefData def = RefData
  { _rdVars :: RefVars
  , _rdBody :: Expr.Body def Ref
  }
Lens.makeLenses ''RefData

data ExprRefs def = ExprRefs
  { _exprRefsUF :: UF.UnionFind
  , _exprRefsData :: RefMap (RefData def)
  }
Lens.makeLenses ''ExprRefs

data Context def = Context
  { _ctxExprRefs :: ExprRefs def
  , -- NOTE: This Map is for 2 purposes: Sharing Refs of loaded Defs
    -- and allowing to specify recursive defs
    _ctxDefRefs :: Map def Ref
  }
Lens.makeLenses ''Context

data LoadedDef def = LoadedDef
  { _ldDef :: def
  , _ldType :: Ref
  }
Lens.makeLenses ''LoadedDef

data TypedValue = TypedValue
  { _tvVal :: {-# UNPACK #-}! Ref
  , _tvType :: {-# UNPACK #-}! Ref
  } deriving (Eq, Ord)
Lens.makeLenses ''TypedValue
instance Show TypedValue where
  show (TypedValue v t) = unwords [show v, ":", show t]

data ScopedTypedValue = ScopedTypedValue
  { _stvTV :: TypedValue
  , _stvScope :: Map Guid Ref
  }
Lens.makeLenses ''ScopedTypedValue