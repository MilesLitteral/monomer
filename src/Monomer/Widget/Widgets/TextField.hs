{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}

module Monomer.Widget.Widgets.TextField (
  TextFieldConfig(..),
  textField,
  textField_,
  textFieldConfig
) where

import Control.Monad
import Control.Lens (ALens', (&), (^#), (#~), (.~), (^?), _Just, non)
import Data.Default
import Data.Maybe
import Data.Text (Text)
import Data.Typeable

import qualified Data.Text as T

import Monomer.Common.Geometry
import Monomer.Common.Style
import Monomer.Common.Tree
import Monomer.Event.Core
import Monomer.Event.Keyboard
import Monomer.Event.Types
import Monomer.Graphics.Drawing
import Monomer.Graphics.Types
import Monomer.Widget.BaseSingle
import Monomer.Widget.Types
import Monomer.Widget.Util

data TextFieldConfig s e = TextFieldConfig {
  _tfcValue :: WidgetValue s Text,
  _tfcOnChange :: [Text -> e],
  _tfcOnChangeReq :: [WidgetRequest s],
  _tfcCaretWidth :: Double
}

data TextFieldState = TextFieldState {
  _tfCurrText :: Text,
  _tfPosition :: Int
} deriving (Eq, Show, Typeable)

textFieldConfig :: WidgetValue s Text -> TextFieldConfig s e
textFieldConfig value = TextFieldConfig {
  _tfcValue = value,
  _tfcOnChange = [],
  _tfcOnChangeReq = [],
  _tfcCaretWidth = 2
}

textFieldState :: TextFieldState
textFieldState = TextFieldState {
  _tfCurrText = "",
  _tfPosition = 0
}

textField :: ALens' s Text -> WidgetInstance s e
textField field = textField_ config where
  config = textFieldConfig (WidgetLens field)

textField_ :: TextFieldConfig s e -> WidgetInstance s e
textField_ config = makeInstance $ makeTextField config textFieldState

makeInstance :: Widget s e -> WidgetInstance s e
makeInstance widget = (defaultWidgetInstance "textField" widget) {
  _wiFocusable = True
}

makeTextField :: TextFieldConfig s e -> TextFieldState -> Widget s e
makeTextField config state = widget where
  widget = createSingle def {
    singleInit = init,
    singleGetState = makeState state,
    singleMerge = merge,
    singleHandleEvent = handleEvent,
    singleUpdateSizeReq = updateSizeReq,
    singleRender = render
  }

  TextFieldState currText currPos = state
  (part1, part2) = T.splitAt currPos currText
  currentValue wenv = widgetValueGet (_weModel wenv) (_tfcValue config)

  init wenv widgetInst = resultWidget newInstance where
    currText = currentValue wenv
    newState = TextFieldState currText 0
    newInstance = widgetInst {
      _wiWidget = makeTextField config newState
    }

  merge wenv oldState widgetInst = resultWidget newInstance where
    TextFieldState _ oldPos = fromMaybe textFieldState (useState oldState)
    currText = currentValue wenv
    newPos = if | T.length currText < oldPos -> T.length currText
                | otherwise -> oldPos
    newState = TextFieldState currText newPos
    newInstance = widgetInst {
      _wiWidget = makeTextField config newState
    }

  handleKeyPress txt tp code
      | isKeyBackspace code && tp > 0 = (T.append (T.init part1) part2, tp - 1)
      | isKeyLeft code && tp > 0 = (txt, tp - 1)
      | isKeyRight code && tp < T.length txt = (txt, tp + 1)
      | isKeyBackspace code || isKeyLeft code || isKeyRight code = (txt, tp)
      | otherwise = (txt, tp)

  handleEvent wenv target evt widgetInst = case evt of
    Click (Point x y) _ -> Just $ resultReqs reqs widgetInst where
      reqs = [SetFocus $ _wiPath widgetInst]

    KeyAction mod code KeyPressed -> Just $ resultReqs reqs newInstance where
      (newText, newPos) = handleKeyPress currText currPos code
      isPaste = isClipboardPaste wenv evt
      isCopy = isClipboardCopy wenv evt
      reqGetClipboard = [GetClipboard (_wiPath widgetInst) | isPaste]
      reqSetClipboard = [SetClipboard (ClipboardText currText) | isCopy]
      reqUpdateModel
        | currText /= newText = widgetValueSet (_tfcValue config) newText
        | otherwise = []
      reqs = reqGetClipboard ++ reqSetClipboard ++ reqUpdateModel
      newState = TextFieldState newText newPos
      newInstance = widgetInst {
        _wiWidget = makeTextField config newState
      }

    TextInput newText -> insertText wenv widgetInst newText

    Clipboard (ClipboardText newText) -> insertText wenv widgetInst newText

    _ -> Nothing

  insertText wenv widgetInst addedText = Just $ resultReqs reqs newInst where
    newText = T.concat [part1, addedText, part2]
    newPos = currPos + T.length addedText
    newState = TextFieldState newText newPos
    reqs = widgetValueSet (_tfcValue config) newText
    newInst = widgetInst {
      _wiWidget = makeTextField config newState
    }

  updateSizeReq wenv widgetInst = newInst where
    style = activeStyle wenv widgetInst
    size = getTextBounds wenv style currText
    sizeReq = SizeReq size FlexibleSize StrictSize
    newInst = widgetInst {
      _wiSizeReq = sizeReq
    }

  render renderer wenv widgetInst = do
    drawStyledBackground renderer _wiViewport style
    Rect tl tt _ _ <- drawStyledText renderer renderArea style currText

    when (isFocused wenv widgetInst) $ do
      let Size sw sh = getTextBounds wenv style part1
      drawRect renderer (Rect (tl + sw) tt caretWidth sh) caretColor Nothing

    where
      WidgetInstance{..} = widgetInst
      ts = _weTimestamp wenv
      renderArea@(Rect rl rt rw rh) = _wiRenderArea
      style = activeStyle wenv widgetInst
      caretAlpha
        | isFocused wenv widgetInst = fromIntegral (ts `mod` 1000) / 1000.0
        | otherwise = 0
      caretColor = Just $ textColor style & alpha .~ caretAlpha
      caretWidth = _tfcCaretWidth config
