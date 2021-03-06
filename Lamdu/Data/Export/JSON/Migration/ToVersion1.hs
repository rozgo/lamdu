-- | Migration support for JSONs with version 0 (no "schemaVersion") to version 1
-- Migration changes:
-- 1. Add {"schemaVersion":1} as head of list
--
-- 2. Move "frozenDefTypes" into "frozenDeps"."defTypes"
--
-- 3. Copy all nominal types into "frozenDeps"."nominals" inside all
-- definitions that use them

{-# LANGUAGE OverloadedStrings #-}
module Lamdu.Data.Export.JSON.Migration.ToVersion1 (migrate) where

import           Control.Applicative ((<|>))
import qualified Control.Lens as Lens
import qualified Data.Aeson as Aeson
import           Data.Foldable (asum)
import qualified Data.Map as Map
import           Data.Map.Utils (setMapIntersection)
import           Data.Set (Set)
import qualified Data.Set as Set

import           Lamdu.Prelude

version1 :: Aeson.Value
version1 =
    mempty
    & Lens.at "schemaVersion" ?~ Aeson.Number 1
    & Aeson.Object

type NominalId = Text
type FrozenNominal = Aeson.Value
type DefId = Text
type FrozenDef = Aeson.Value

children :: Aeson.Value -> [Aeson.Value]
children (Aeson.Object x) = x ^.. Lens.folded
children (Aeson.Array  x) = x ^.. Lens.folded
children Aeson.Null {} = []
children Aeson.Bool {} = []
children Aeson.Number {} = []
children Aeson.String {} = []

asIdentifierSet :: Maybe Aeson.Value -> Either Text (Set Text)
asIdentifierSet Nothing = Right mempty
asIdentifierSet (Just (Aeson.String x)) = Set.singleton x & Right
asIdentifierSet (Just _) = Left "identifier must be a string"

scanVars :: Aeson.Value -> Either Text (Set DefId)
scanVars val =
    (<>)
    <$> (traverse scanVars (children val) <&> mconcat)
    <*> case val of
        Aeson.Object obj -> obj ^. Lens.at "var" & asIdentifierSet
        _ -> pure mempty

scanNomIds :: Aeson.Value -> Either Text (Set NominalId)
scanNomIds val =
    (<>)
    <$> recurse
    <*> case val of
        Aeson.Object obj ->
            (<>)
            <$> asIdentifierSet (obj ^. Lens.at "fromNomId")
            <*> asIdentifierSet (obj ^. Lens.at "toNomId")
        _ -> pure mempty
    where
        recurse :: Either Text (Set NominalId)
        recurse = children val & traverse scanNomIds <&> mconcat

addFrozenDeps ::
    Map NominalId FrozenNominal -> Aeson.Value -> Aeson.Object ->
    Either Text Aeson.Object
addFrozenDeps nominalMap frozenDefTypes defObj =
    do
        usedNoms <-
            case defObj ^. Lens.at "val" of
            Nothing -> Left "definition with no val"
            Just val -> scanNomIds val
        unless (Set.null (usedNoms `Set.difference` Map.keysSet nominalMap))
            (Left "undefined noms used")
        let frozenNominals =
                setMapIntersection usedNoms nominalMap
                & Aeson.toJSON
        let frozenDeps =
                mempty
                & Lens.at "defTypes" ?~ frozenDefTypes
                & Lens.at "nominals" ?~ frozenNominals
                & Aeson.Object
        defObj
            & Lens.at "frozenDeps" ?~ frozenDeps
            & pure

convertBuiltin :: Aeson.Object -> Aeson.Value -> Either Text Aeson.Object
convertBuiltin obj builtin =
    do
        bobj <-
            case builtin of
            Aeson.Object x -> return x
            _ -> Left "builtin not an object"
        name <-
            case bobj ^. Lens.at "name" of
            Nothing -> Left "builtin with no name"
            Just x -> return x
        scheme <-
            case bobj ^. Lens.at "scheme" of
            Nothing -> Left "builin with no scheme"
            Just x -> return x
        obj
            & Lens.at "builtin" ?~ name
            & Lens.at "typ" ?~ scheme
            & pure

replDefExpr ::
    Map NominalId FrozenNominal -> Map DefId FrozenDef ->
    Aeson.Value -> Either Text Aeson.Value
replDefExpr nominalMap defMap val =
    do
        usedVars <- scanVars val
        let frozenDefs = setMapIntersection usedVars defMap & Aeson.toJSON
        mempty
            & Lens.at "val" ?~ val
            & addFrozenDeps nominalMap frozenDefs
            <&> Aeson.Object

-- | Represents "forall a. a"
schemeAny :: Aeson.Value
schemeAny =
    mempty
    & Lens.at "schemeBinders" ?~
      ( mempty
        & Lens.at "typeVars" ?~ Aeson.toJSON [var]
        & Aeson.Object
      )
    & Lens.at "schemeType" ?~
      ( mempty
        & Lens.at "typeVar" ?~ var
        & Aeson.Object
      )
    & Aeson.Object
    where
        var = Aeson.String "61"

fixScheme :: Aeson.Value -> Either Text Aeson.Value
fixScheme (Aeson.String s)
    | s == "NoExportedType" = return schemeAny
fixScheme o@Aeson.Object{} = return o
fixScheme _ = Left "Malformed scheme"

migrateEntity ::
    Map NominalId FrozenNominal -> Map DefId FrozenDef ->
    Aeson.Value -> Either Text Aeson.Value
migrateEntity nominalMap defMap (Aeson.Object obj) =
    asum
    [ Left "found unexpected version" <$ obj ^. Lens.at "schemaVersion"
    , obj ^. Lens.at "typ" <&>
        \typ ->
        do
            fixedTyp <- fixScheme typ
            let prevFrozenTypes =
                    obj ^. Lens.at "frozenDefTypes"
                    & fromMaybe (Aeson.Object mempty)
            obj
                & Lens.at "frozenDefTypes" .~ Nothing
                & Lens.at "typ" ?~ fixedTyp
                & addFrozenDeps nominalMap prevFrozenTypes
    , obj ^. Lens.at "builtin" <&> convertBuiltin obj
    , obj ^. Lens.at "repl" <&>
        \replVal ->
        do
            defExpr <- replDefExpr nominalMap defMap replVal
            obj
                & Lens.at "repl" ?~ defExpr
                & return
    ]
    & fromMaybe (Right obj)
    <&> Aeson.Object
migrateEntity _ _ _ = Left "Expecting object"

collectNominals :: Aeson.Value -> Either Text (Map NominalId FrozenNominal)
collectNominals (Aeson.Object obj) =
    case obj ^. Lens.at "nom" of
    Just (Aeson.String nomId) ->
        case obj ^. Lens.at "nomType" of
        Nothing -> Left "Malformed 'nom' node"
        Just nomType ->
            mempty & Lens.at nomId ?~ frozenNom & Right
            where
                frozenNom =
                    mempty
                    & Lens.at "nomType" ?~ nomType
                    & Lens.at "typeParams" .~ (obj ^. Lens.at "typeParams")
                    & Aeson.Object
    Just _ -> Left "Malformed 'nom' id"
    Nothing -> Right mempty
collectNominals _ = Right mempty

collectDefs :: Aeson.Value -> Either Text (Map DefId FrozenDef)
collectDefs (Aeson.Object obj) =
    case obj ^. Lens.at "def" of
    Just (Aeson.String defId) ->
        do
            builtinType <-
                case obj ^. Lens.at "builtin" of
                Just (Aeson.Object b) -> b ^. Lens.at "scheme" & Right
                Just _ -> Left "Malformed 'buitlin' node"
                _ -> Right Nothing
            case obj ^. Lens.at "typ" <|> builtinType of
                Just defType ->
                    do
                        fixed <- fixScheme defType
                        mempty & Lens.at defId ?~ fixed & Right
                Nothing -> Left "Malformed 'def' node"
    Just _ -> Left "Malformed 'def' id"
    Nothing -> Right mempty
collectDefs _ = Right mempty

migrate :: Aeson.Value -> Either Text Aeson.Value
migrate (Aeson.Array vals) =
    do
        nominalMap <- traverse collectNominals vals <&> (^. traverse)
        defMap <- traverse collectDefs vals <&> (^. traverse)
        newVals <- traverse (migrateEntity nominalMap defMap) vals
        Lens._Cons # (version1, newVals)
            & Aeson.Array & pure
migrate _ = Left "top-level should be array"
