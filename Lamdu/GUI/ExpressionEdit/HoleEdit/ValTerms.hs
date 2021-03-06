{-# LANGUAGE LambdaCase, NoImplicitPrelude, OverloadedStrings #-}
module Lamdu.GUI.ExpressionEdit.HoleEdit.ValTerms
    ( body
    ) where

import           Data.Store.Property (Property)
import qualified Data.Store.Property as Property
import qualified Data.Text as Text
import           Lamdu.Formatting (Format(..))
import qualified Lamdu.Sugar.Names.Get as NamesGet
import           Lamdu.Sugar.Names.Types (Name(..), NameCollision(..))
import qualified Lamdu.Sugar.Types as Sugar

import           Lamdu.Prelude

ofName :: Name m -> Text
ofName (Name _ NoCollision _ varName) = varName
ofName (Name _ (Collision suffix) _ varName) = varName <> Text.pack (show suffix)

formatProp :: Format a => Property m a -> Text
formatProp i = i ^. Property.pVal & format

formatLiteral :: Sugar.Literal (Property m) -> Text
formatLiteral (Sugar.LiteralNum i) = formatProp i
formatLiteral (Sugar.LiteralText i) = formatProp i
formatLiteral (Sugar.LiteralBytes i) = formatProp i

bodyShape :: Sugar.Body (Name m) m expr -> [Text]
bodyShape = \case
    Sugar.BodyLam {} -> ["lambda", "\\", "Λ", "λ"]
    Sugar.BodyApply {} -> ["Apply"]
    Sugar.BodyRecord r ->
        ["record", "{}", "()"] ++
        case r of
        Sugar.Record [] Sugar.ClosedRecord{} _ -> ["empty"]
        _ -> []
    Sugar.BodyGetField gf ->
        [".", "field", "." <> ofName (gf ^. Sugar.gfTag . Sugar.tagGName)]
    Sugar.BodyCase cas ->
        ["case", ":"] ++
        case cas of
            Sugar.Case Sugar.LambdaCase [] Sugar.ClosedCase{} _ _ -> ["absurd"]
            _ -> []
    Sugar.BodyInject {} -> ["[]"]
    Sugar.BodyLiteral i -> [formatLiteral i]
    Sugar.BodyGetVar Sugar.GetParamsRecord {} -> ["Params"]
    Sugar.BodyGetVar {} -> []
    Sugar.BodyToNom {} -> []
    Sugar.BodyFromNom {} -> []
    Sugar.BodyHole {} -> []
    Sugar.BodyInjectedExpression {} -> []

bodyNames :: Monad m => Sugar.Body (Name m) m expr -> [Text]
bodyNames = \case
    Sugar.BodyGetVar Sugar.GetParamsRecord {} -> []
    Sugar.BodyLam {} -> []
    b -> NamesGet.fromBody b <&> ofName

body :: Monad m => Sugar.Body (Name m) m expr -> [Text]
body = bodyShape <> bodyNames
