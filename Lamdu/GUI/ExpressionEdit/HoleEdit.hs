module Lamdu.GUI.ExpressionEdit.HoleEdit
  ( make
  ) where

import Control.Applicative ((<$>))
import Control.Lens.Operators
import Control.Monad (guard)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Maybe (MaybeT(..))
import Control.MonadA (MonadA)
import Data.Maybe (fromMaybe)
import Data.Maybe.Utils (maybeToMPlus)
import Lamdu.GUI.ExpressionEdit.HoleEdit.Info (HoleInfo(..), diveIntoHole)
import Lamdu.GUI.ExpressionGui (ExpressionGui(..))
import Lamdu.GUI.ExpressionGui.Monad (ExprGuiM)
import qualified Control.Lens as Lens
import qualified Data.Store.Transaction as Transaction
import qualified Graphics.UI.Bottle.Widget as Widget
import qualified Lamdu.GUI.ExpressionEdit.HoleEdit.Closed as HoleClosed
import qualified Lamdu.GUI.ExpressionEdit.HoleEdit.Info as HoleInfo
import qualified Lamdu.GUI.ExpressionEdit.HoleEdit.Open as HoleOpen
import qualified Lamdu.GUI.ExpressionGui as ExpressionGui
import qualified Lamdu.GUI.ExpressionGui.Monad as ExprGuiM
import qualified Lamdu.GUI.WidgetEnvT as WE
import qualified Lamdu.Sugar.Types as Sugar

make ::
  MonadA m =>
  Sugar.Hole Sugar.Name m (ExprGuiM.SugarExpr m) ->
  Sugar.Payload Sugar.Name m ExprGuiM.Payload ->
  Widget.Id -> ExprGuiM m (ExpressionGui m)
make hole pl myId = do
  (delegateDestId, closed) <- HoleClosed.make hole pl myId
  let
    closedSize = closed ^. ExpressionGui.egWidget . Widget.wSize
    resize gui =
      ExpressionGui.truncateSize
      ( closedSize
        & Lens._1 %~ max (gui ^. ExpressionGui.egWidget . Widget.wSize . Lens._1)
      ) gui
  ExprGuiM.assignCursor myId delegateDestId $
    fromMaybe closed <$>
    runMaybeT (resize <$> tryActiveHole hole pl myId)

tryActiveHole ::
  MonadA m =>
  Sugar.Hole Sugar.Name m (ExprGuiM.SugarExpr m) ->
  Sugar.Payload Sugar.Name m ExprGuiM.Payload ->
  Widget.Id ->
  MaybeT (ExprGuiM m) (ExpressionGui m)
tryActiveHole hole pl myId = do
  isSelected <-
    lift . ExprGuiM.widgetEnv . WE.isSubCursor $ diveIntoHole myId
  guard isSelected
  storedGuid <- maybeToMPlus $ pl ^? Sugar.plActions . Lens._Just . Sugar.storedGuid
  actions <- maybeToMPlus $ hole ^. Sugar.holeMActions
  inferred <- maybeToMPlus $ hole ^. Sugar.holeMInferred
  stateProp <- lift . ExprGuiM.transaction $ HoleInfo.assocStateRef storedGuid ^. Transaction.mkProperty
  lift $ HoleOpen.make pl HoleInfo
    { hiStoredGuid = storedGuid
    , hiActions = actions
    , hiInferred = inferred
    , hiId = myId
    , hiState = stateProp
    , hiHoleGuids = pl ^. Sugar.plData . ExprGuiM.plHoleGuids
    , hiMArgument = hole ^. Sugar.holeMArg
    }
