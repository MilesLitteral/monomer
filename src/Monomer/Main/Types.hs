{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}

module Monomer.Main.Types where

import Control.Concurrent.Async
import Control.Monad.State
import Data.Typeable (Typeable)
import Data.Sequence (Seq)
import Lens.Micro.TH (makeLenses)

import Monomer.Common.Geometry
import Monomer.Common.Tree
import Monomer.Event.Types
import Monomer.Widget.Types

type MonomerM s e m = (MonadState (MonomerContext s e) m, MonadIO m, Eq s)
type UIBuilder s e m = s -> WidgetInstance s e m
type AppEventHandler s e = s -> e -> EventResponse s e

data EventResponse s e = State s | StateEvent s e | Task s (IO (Maybe e))

data MonomerApp s e m = MonomerApp {
  _uiBuilder :: UIBuilder s e m,
  _appEventHandler :: AppEventHandler s e
}

data MonomerContext s e = MonomerContext {
  _appContext :: s,
  _windowSize :: Rect,
  _useHiDPI :: Bool,
  _devicePixelRate :: Double,
  _inputStatus :: InputStatus,
  _focused :: Path,
  _latestHover :: Maybe Path,
  _userTasks :: [UserTask (Maybe e)],
  _widgetTasks :: Seq WidgetTask
}

data UserTask e = UserTask {
  _userTask :: Async e
}

data WidgetTask = forall a . Typeable a => WidgetTask {
  _widgetTaskPath :: Path,
  _widgetTask :: Async a
}

makeLenses ''MonomerContext