{-# LANGUAGE RankNTypes #-}

module Monomer.Widgets.Confirm (
  confirm,
  confirm_
) where

import Control.Applicative ((<|>))
import Control.Lens ((&), (.~), (<>~))
import Data.Default
import Data.Maybe
import Data.Text (Text)

import Monomer.Core
import Monomer.Core.Combinators

import Monomer.Widgets.Box
import Monomer.Widgets.Button
import Monomer.Widgets.Composite
import Monomer.Widgets.Icon
import Monomer.Widgets.Label
import Monomer.Widgets.Spacer
import Monomer.Widgets.Stack

import qualified Monomer.Lens as L

data ConfirmCfg = ConfirmCfg {
  _cfcTitle :: Maybe Text,
  _cfcAccept :: Maybe Text,
  _cfcCancel :: Maybe Text
}

instance Default ConfirmCfg where
  def = ConfirmCfg {
    _cfcTitle = Nothing,
    _cfcAccept = Nothing,
    _cfcCancel = Nothing
  }

instance Semigroup ConfirmCfg where
  (<>) a1 a2 = ConfirmCfg {
    _cfcTitle = _cfcTitle a2 <|> _cfcTitle a1,
    _cfcAccept = _cfcAccept a2 <|> _cfcAccept a1,
    _cfcCancel = _cfcCancel a2 <|> _cfcCancel a1
  }

instance Monoid ConfirmCfg where
  mempty = def

instance CmbAcceptCaption ConfirmCfg where
  acceptCaption t = def {
    _cfcAccept = Just t
  }

instance CmbCancelCaption ConfirmCfg where
  cancelCaption t = def {
    _cfcCancel = Just t
  }

confirm :: (WidgetModel s, WidgetEvent e) => Text -> e -> e -> WidgetNode s e
confirm message acceptEvt cancelEvt = confirm_ message acceptEvt cancelEvt def

confirm_
  :: (WidgetModel s, WidgetEvent e)
  => Text
  -> e
  -> e
  -> [ConfirmCfg]
  -> WidgetNode s e
confirm_ message acceptEvt cancelEvt configs = newNode where
  config = mconcat configs
  createUI = buildUI message acceptEvt cancelEvt config
  newNode = compositeExt "confirm" () Nothing createUI handleEvent

buildUI :: Text -> e -> e -> ConfirmCfg -> WidgetEnv s e -> s -> WidgetNode s e
buildUI message acceptEvt cancelEvt config wenv model = confirmBox where
  title = fromMaybe "" (_cfcTitle config)
  accept = fromMaybe "Accept" (_cfcAccept config)
  cancel = fromMaybe "Cancel" (_cfcCancel config)
  emptyOverlayColor = themeEmptyOverlayColor wenv
  acceptBtn = mainButton accept acceptEvt
  cancelBtn = button cancel cancelEvt
  buttons = hstack [ acceptBtn, spacer, cancelBtn ]
  closeIcon = icon IconClose & L.info . L.style .~ themeDialogCloseIcon wenv
  confirmTree = vstack [
      hstack [
        label title & L.info . L.style .~ themeDialogTitle wenv,
        box_ closeIcon [onClick cancelEvt]
      ],
      label_ message [textMultiLine]
        & L.info . L.style .~ themeDialogBody wenv,
      box_ buttons [alignLeft]
        & L.info . L.style <>~ themeDialogButtons wenv
    ] & L.info . L.style .~ themeDialogFrame wenv
  confirmBox = box_ confirmTree [onClickEmpty cancelEvt]
    & L.info . L.style .~ emptyOverlayColor

handleEvent :: WidgetEnv s e -> s -> e -> [EventResponse s e e]
handleEvent wenv model evt = [Report evt]
