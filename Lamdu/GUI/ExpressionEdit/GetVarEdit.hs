{-# LANGUAGE NoImplicitPrelude, RecordWildCards, OverloadedStrings #-}
module Lamdu.GUI.ExpressionEdit.GetVarEdit
    ( make
    ) where

import qualified Control.Lens as Lens
import qualified Data.ByteString.Char8 as SBS8
import           Data.Store.Transaction (Transaction)
import qualified Graphics.DrawingCombinators as Draw
import qualified Graphics.UI.Bottle.EventMap as E
import           Graphics.UI.Bottle.Font (Underline(..))
import qualified Graphics.UI.Bottle.Widget as Widget
import           Graphics.UI.Bottle.Widget.Aligned (AlignedWidget)
import qualified Graphics.UI.Bottle.Widget.Aligned as AlignedWidget
import           Graphics.UI.Bottle.Widget.TreeLayout (TreeLayout)
import qualified Graphics.UI.Bottle.Widget.TreeLayout as TreeLayout
import qualified Graphics.UI.Bottle.Widgets as BWidgets
import qualified Graphics.UI.Bottle.WidgetsEnvT as WE
import           Lamdu.Calc.Type.Scheme (schemeType)
import           Lamdu.Config (Config)
import qualified Lamdu.Config as Config
import qualified Lamdu.Data.Ops as DataOps
import           Lamdu.GUI.ExpressionGui (ExpressionGui)
import qualified Lamdu.GUI.ExpressionGui as ExpressionGui
import           Lamdu.GUI.ExpressionGui.Monad (ExprGuiM)
import qualified Lamdu.GUI.ExpressionGui.Monad as ExprGuiM
import qualified Lamdu.GUI.ExpressionGui.Types as ExprGuiT
import qualified Lamdu.GUI.LightLambda as LightLambda
import qualified Lamdu.GUI.TypeView as TypeView
import qualified Lamdu.GUI.WidgetIds as WidgetIds
import           Lamdu.Sugar.Names.Types (Name(..))
import qualified Lamdu.Sugar.Types as Sugar

import           Lamdu.Prelude

makeSimpleView ::
    (Monad f, Monad m) =>
    Draw.Color -> Name m -> Widget.Id ->
    ExprGuiM m (ExpressionGui f)
makeSimpleView color name myId =
    ExprGuiM.widgetEnv (BWidgets.makeFocusableView myId)
    <*> (ExpressionGui.makeNameView name (Widget.toAnimId myId) <&> Widget.fromView)
    & ExprGuiM.withFgColor color
    <&> TreeLayout.fromCenteredWidget

makeParamsRecord ::
    Monad m => Widget.Id -> Sugar.ParamsRecordVar (Name m) ->
    ExprGuiM m (ExpressionGui m)
makeParamsRecord myId paramsRecordVar =
    do
        config <- ExprGuiM.readConfig
        let Config.Name{..} = Config.name config
        sequence
            [ ExpressionGui.makeLabel "Params {"
              (Widget.toAnimId myId <> ["prefix"])
              <&> TreeLayout.fromAlignedWidget
            , ExpressionGui.combineSpaced Nothing
              <*>
              ( fieldNames
                & Lens.itraverse
                (\i fieldName ->
                    Widget.joinId myId ["params", SBS8.pack (show (i::Int))]
                    & makeSimpleView parameterColor fieldName
                )
              )
            , ExpressionGui.makeLabel "}" (Widget.toAnimId myId <> ["suffix"])
              <&> TreeLayout.fromAlignedWidget
            ] <&> ExpressionGui.combine
    where
        Sugar.ParamsRecordVar fieldNames = paramsRecordVar

makeNameRef ::
    Monad m => Widget.Id -> Sugar.NameRef name m ->
    (name -> Widget.Id -> ExprGuiM m (ExpressionGui m)) ->
    ExprGuiM m (ExpressionGui m)
makeNameRef myId nameRef makeView =
    do
        cp <- ExprGuiM.readCodeAnchors
        config <- ExprGuiM.readConfig
        let jumpToDefinitionEventMap =
                Widget.keysEventMapMovesCursor
                (Config.jumpToDefinitionKeys config ++ Config.extractKeys config)
                (E.Doc ["Navigation", "Jump to definition"]) $
                do
                    DataOps.savePreJumpPosition cp myId
                    WidgetIds.fromEntityId <$> nameRef ^. Sugar.nrGotoDefinition
        makeView (nameRef ^. Sugar.nrName) myId
            <&> TreeLayout.widget %~ Widget.weakerEvents jumpToDefinitionEventMap

makeInlineEventMap ::
    Monad m =>
    Config -> Sugar.BinderVarInline m ->
    Widget.EventMap (Transaction m Widget.EventResult)
makeInlineEventMap config (Sugar.InlineVar inline) =
    inline <&> WidgetIds.fromEntityId
    & Widget.keysEventMapMovesCursor (Config.inlineKeys config)
      (E.Doc ["Edit", "Inline"])
makeInlineEventMap config (Sugar.CannotInlineDueToUses (x:_)) =
    WidgetIds.fromEntityId x & return
    & Widget.keysEventMapMovesCursor (Config.inlineKeys config)
      (E.Doc ["Navigation", "Jump to next use"])
makeInlineEventMap _ _ = mempty

definitionTypeChangeBox ::
    Monad m =>
    Sugar.DefinitionOutdatedType m -> Widget.Id -> ExprGuiM m (AlignedWidget a)
definitionTypeChangeBox info myId =
    do
        headerLabel <-
            ExpressionGui.makeLabel "Type changed from" animId
        typeWhenUsed <-
            mkTypeWidget "typeWhenUsed" (info ^. Sugar.defTypeWhenUsed)
        sepLabel <- ExpressionGui.makeLabel "to" animId
        typeCurrent <- mkTypeWidget "typeCurrent" (info ^. Sugar.defTypeCurrent)
        config <- ExprGuiM.readConfig
        AlignedWidget.vbox 0
            [headerLabel, typeWhenUsed, sepLabel, typeCurrent]
            & AlignedWidget.alignment .~ 0
            & AlignedWidget.widget %~
                Widget.backgroundColor (animId ++ ["getdef background"])
                -- TODO: which background color to use?
                -- This and hole should probably use the same background,
                -- but it should have a different name to represent that.
                (Config.holeOpenBGColor (Config.hole config))
            & return
    where
        mkTypeWidget idSuffix scheme =
            TypeView.make (scheme ^. schemeType) (animId ++ [idSuffix])
            <&> Widget.fromView <&> AlignedWidget.fromCenteredWidget
        animId = Widget.toAnimId myId

processDefinitionWidget ::
    Monad m =>
    Sugar.DefinitionForm m -> Widget.Id ->
    ExprGuiM m (TreeLayout a) -> ExprGuiM m (TreeLayout a)
processDefinitionWidget Sugar.DefUpToDate _myId mkLayout = mkLayout
processDefinitionWidget Sugar.DefDeleted myId mkLayout =
    mkLayout
    & Lens.mapped . TreeLayout.widget . Widget.view %~
        ExpressionGui.deletionDiagonal 0.1 (Widget.toAnimId myId)
processDefinitionWidget (Sugar.DefTypeChanged info) myId mkLayout =
    do
        layout <-
            ExprGuiM.withLocalUnderline Underline
                { _underlineColor = Draw.Color 1 0 0 1
                , _underlineWidth = 2
                }
            mkLayout
        isSelected <- ExprGuiM.widgetEnv $ WE.isSubCursor myId
        if isSelected
            then
            do
                box <- definitionTypeChangeBox info myId
                layout
                    & TreeLayout.alignment . _1 .~ 0
                    & TreeLayout.alignedWidget %~
                        AlignedWidget.addAfter AlignedWidget.Vertical
                        [box `AlignedWidget.hoverInPlaceOf` AlignedWidget.empty]
                    & return
            else return layout

make ::
    Monad m =>
    Sugar.GetVar (Name m) m ->
    Sugar.Payload m ExprGuiT.Payload ->
    ExprGuiM m (ExpressionGui m)
make getVar pl =
    do
        config <- ExprGuiM.readConfig
        let Config.Name{..} = Config.name config
        ExpressionGui.stdWrap pl
            <*>
            case getVar of
            Sugar.GetBinder binderVar ->
                case binderVar ^. Sugar.bvForm of
                Sugar.GetLet -> (letColor, id)
                Sugar.GetDefinition defForm ->
                    ( definitionColor
                    , processDefinitionWidget defForm myId
                    )
                & \(color, processDef) ->
                    makeSimpleView color
                    <&> Lens.mapped %~ processDef
                    & makeNameRef myId (binderVar ^. Sugar.bvNameRef)
                    <&> TreeLayout.widget %~
                    Widget.weakerEvents
                    (makeInlineEventMap config (binderVar ^. Sugar.bvInline))
            Sugar.GetParam param ->
                case param ^. Sugar.pBinderMode of
                Sugar.LightLambda ->
                    makeSimpleView nameOriginFGColor
                    <&> Lens.mapped %~
                        LightLambda.withUnderline (Config.lightLambda config)
                _ -> makeSimpleView parameterColor
                & makeNameRef myId (param ^. Sugar.pNameRef)
            Sugar.GetParamsRecord paramsRecordVar -> makeParamsRecord myId paramsRecordVar
    where
        myId = WidgetIds.fromExprPayload pl
