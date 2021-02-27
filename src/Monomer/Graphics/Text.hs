{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleContexts #-}

module Monomer.Graphics.Text (
  calcTextSize,
  calcTextSize_,
  computeTextRect,
  getTextLinesSize,
  fitTextToRect,
  fitTextToWidth,
  alignTextLines,
  moveTextLines,
  getGlyphsMin,
  getGlyphsMax
) where

import Control.Lens ((&), (^.), (+~))
import Data.Default
import Data.List (foldl')
import Data.Maybe
import Data.Sequence (Seq(..), (<|), (|>))
import Data.Text (Text)

import qualified Data.Sequence as Seq
import qualified Data.Text as T

import Monomer.Core
import Monomer.Core.BasicTypes
import Monomer.Core.StyleTypes
import Monomer.Core.StyleUtil
import Monomer.Graphics.Types

import Monomer.Lens as L

type GlyphGroup = Seq GlyphPos

calcTextSize :: Renderer -> StyleState -> Text -> Size
calcTextSize renderer style !text = size where
  size = calcTextSize_ renderer style SingleLine KeepSpaces Nothing Nothing text

calcTextSize_
  :: Renderer
  -> StyleState
  -> TextMode
  -> TextTrim
  -> Maybe Double
  -> Maybe Int
  -> Text
  -> Size
calcTextSize_ renderer style mode trim mwidth mlines text = newSize where
  font = styleFont style
  fontSize = styleFontSize style
  !metrics = computeTextMetrics renderer font fontSize
  width = fromMaybe maxNumericValue mwidth
  textLinesW = fitTextToWidth renderer style width trim text
  textLines
    | mode == SingleLine = Seq.take 1 textLinesW
    | isJust mlines = Seq.take (fromJust mlines) textLinesW
    | otherwise = textLinesW
  newSize
    | not (Seq.null textLines) = getTextLinesSize textLines
    | otherwise = Size 0 (_txmLineH metrics)

computeTextRect
  :: Renderer
  -> Rect
  -> Font
  -> FontSize
  -> AlignTH
  -> AlignTV
  -> Text
  -> Rect
computeTextRect renderer containerRect font fontSize ha va text = textRect where
  Rect x y w h = containerRect
  Size tw _ = computeTextSize renderer font fontSize text
  TextMetrics asc desc lineh = computeTextMetrics renderer font fontSize
  th = lineh
  tx | ha == ATLeft = x
     | ha == ATCenter = x + (w - tw) / 2
     | otherwise = x + (w - tw)
  ty | va == ATTop = y + asc
     | va == ATMiddle = y + h + desc - (h - th) / 2
     | otherwise = y + h + desc

  textRect = Rect {
    _rX = tx,
    _rY = ty - th,
    _rW = tw,
    _rH = th
  }

fitTextToRect
  :: Renderer
  -> StyleState
  -> TextOverflow
  -> TextMode
  -> TextTrim
  -> Maybe Int
  -> Rect
  -> Text
  -> Seq TextLine
fitTextToRect renderer style ovf mode trim mlines !rect !text = newLines where
  Rect cx cy cw ch = rect
  font = styleFont style
  fontSize = styleFontSize style
  textMetrics = computeTextMetrics renderer font fontSize
  maxHeight = case mlines of
    Just maxLines -> min ch (fromIntegral maxLines * textMetrics ^. L.lineH)
    _ -> ch
  textLinesW = fitTextToWidth renderer style cw trim text
  fittedLines = fitTextLinesToH renderer style ovf cw maxHeight textLinesW
  newLines
    | mode == MultiLine = fittedLines
    | otherwise = Seq.take 1 fittedLines

alignTextLines :: StyleState -> Rect -> Seq TextLine -> Seq TextLine
alignTextLines style parentRect textLines = newTextLines where
  Rect _ py _ ph = parentRect
  Size _ th = getTextLinesSize textLines
  alignH = styleTextAlignH style
  alignV = styleTextAlignV style
  alignOffsetY = case alignV of
    ATTop -> 0
    ATMiddle -> (ph - th) / 2
    _ -> ph - th
  offsetY = py + alignOffsetY
  newTextLines = fmap (alignTextLine parentRect offsetY alignH) textLines

alignTextLine :: Rect -> Double -> AlignTH -> TextLine -> TextLine
alignTextLine parentRect offsetY alignH textLine = newTextLine where
  Rect px _ pw _ = parentRect
  Rect tx ty tw th = _tlRect textLine
  alignOffsetX = case alignH of
    ATLeft -> 0
    ATCenter -> (pw - tw) / 2
    ATRight -> pw - tw
  offsetX = px + alignOffsetX
  newTextLine = textLine {
    _tlRect = Rect (tx + offsetX) (ty + offsetY) tw th
  }

fitTextLinesToH
  :: Renderer
  -> StyleState
  -> TextOverflow
  -> Double
  -> Double
  -> Seq TextLine
  -> Seq TextLine
fitTextLinesToH renderer style overflow w h Empty = Empty
fitTextLinesToH renderer style overflow w h (g1 :<| g2 :<| gs)
  | overflow == Ellipsis && h >= g1H + g2H = g1 :<| rest
  | overflow == Ellipsis && h >= g1H = Seq.singleton ellipsisG1
  | overflow == ClipText && h >= g1H = g1 :<| rest
  where
    g1H = _sH (_tlSize g1)
    g2H = _sH (_tlSize g2)
    newH = h - g1H
    rest = fitTextLinesToH renderer style overflow w newH (g2 :<| gs)
    ellipsisG1 = addEllipsisToTextLine renderer style w g1
fitTextLinesToH renderer style overflow w h (g :<| gs)
  | h > 0 = Seq.singleton newG
  | otherwise = Empty
  where
    gW = _sW (_tlSize g)
    newG
      | overflow == Ellipsis && w < gW = addEllipsisToTextLine renderer style w g
      | otherwise = g

fitTextToWidth
  :: Renderer
  -> StyleState
  -> Double
  -> TextTrim
  -> Text
  -> Seq TextLine
fitTextToWidth renderer style width trim text = resultLines where
  font = styleFont style
  fSize = styleFontSize style
  !metrics = computeTextMetrics renderer font fSize
  lineH = _txmLineH metrics
  helper acc line = (cLines <> newLines, newTop) where
    (cLines, cTop) = acc
    newLines = fitSingleTextToW renderer font fSize metrics cTop width trim line
    newTop = cTop + fromIntegral (Seq.length newLines) * lineH
  (resultLines, _) = foldl' helper (Empty, 0) (T.lines text)

fitSingleTextToW
  :: Renderer
  -> Font
  -> FontSize
  -> TextMetrics
  -> Double
  -> Double
  -> TextTrim
  -> Text
  -> Seq TextLine
fitSingleTextToW renderer font fSize metrics top width trim text = result where
  spaces = T.replicate 4 " "
  -- Temporary solution. It should return empty line, not one with space
  newText
    | text /= "" = T.replace "\t" spaces text
    | otherwise = " "
  !glyphs = computeGlyphsPos renderer font fSize newText
  -- Do not break line on trailing spaces, they are removed in the next step
  -- In the case of KeepSpaces, lines with only spaces (empty looking) are valid
  keepTailSpaces = trim == TrimSpaces
  groups = fitGroups (splitGroups glyphs) width keepTailSpaces
  resetGroups
    | trim == TrimSpaces = fmap (resetGlyphs . trimGlyphs) groups
    | otherwise = fmap resetGlyphs groups
  result = Seq.mapWithIndex (buildTextLine metrics top) resetGroups

buildTextLine :: TextMetrics -> Double -> Int -> Seq GlyphPos -> TextLine
buildTextLine metrics top idx glyphs = textLine where
  lineH = _txmLineH metrics
  x = 0
  y = top + fromIntegral idx * lineH
  width = getGlyphsWidth glyphs
  height = lineH
  text = T.pack . reverse $ foldl' (\ac g -> _glpGlyph g : ac) [] glyphs
  textLine = TextLine {
    _tlText = text,
    _tlSize = Size width height,
    _tlRect = Rect x y width height,
    _tlGlyphs = glyphs,
    _tlMetrics = metrics
  }

addEllipsisToTextLine
  :: Renderer
  -> StyleState
  -> Double
  -> TextLine
  -> TextLine
addEllipsisToTextLine renderer style width textLine = newTextLine where
  TextLine text textSize textRect textGlyphs textMetrics = textLine
  Size tw th = textSize
  Size dw dh = calcTextSize renderer style "..."
  font = styleFont style
  fontSize = styleFontSize style
  targetW = width - tw
  dropHelper (idx, w) g
    | _glpW g + w <= dw = (idx + 1, _glpW g + w)
    | otherwise = (idx, w)
  (dropChars, _) = foldl' dropHelper (0, targetW) (Seq.reverse textGlyphs)
  newText = T.dropEnd dropChars text <> "..."
  !newGlyphs = computeGlyphsPos renderer font fontSize newText
  newW = getGlyphsWidth newGlyphs
  newTextLine = TextLine {
    _tlText = newText,
    _tlSize = textSize { _sW = newW },
    _tlRect = textRect { _rW = newW },
    _tlGlyphs = newGlyphs,
    _tlMetrics = textMetrics
  }

fitGroups :: Seq GlyphGroup -> Double -> Bool -> Seq GlyphGroup
fitGroups Empty _ _ = Empty
fitGroups (g :<| gs) !width !keepTailSpaces = currentLine <| extraLines where
  gW = getGlyphsWidth g
  gMax = getGlyphsMax g
  extraGroups = fitExtraGroups gs (width - gW) gMax keepTailSpaces
  (lineGroups, remainingGroups) = extraGroups
  currentLine = g <> lineGroups
  extraLines = fitGroups remainingGroups width keepTailSpaces

fitExtraGroups
  :: Seq GlyphGroup
  -> Double
  -> Double
  -> Bool
  -> (Seq GlyphPos, Seq GlyphGroup)
fitExtraGroups Empty _ _ _ = (Empty, Empty)
fitExtraGroups (g :<| gs) !width !prevGMax !keepTailSpaces
  | gW + wDiff <= width || keepSpace = (g <> newFit, newRest)
  | otherwise = (Empty, g :<| gs)
  where
    gW = getGlyphsWidth g
    gMin = getGlyphsMin g
    gMax = getGlyphsMax g
    wDiff = gMin - prevGMax
    remWidth = width - (gW + wDiff)
    keepSpace = keepTailSpaces && isSpaceGroup g
    (newFit, newRest) = fitExtraGroups gs remWidth gMax keepTailSpaces

getGlyphsMin :: Seq GlyphPos -> Double
getGlyphsMin Empty = 0
getGlyphsMin (g :<| gs) = _glpXMin g

getGlyphsMax :: Seq GlyphPos -> Double
getGlyphsMax Empty = 0
getGlyphsMax (gs :|> g) = _glpXMax g

getGlyphsWidth :: Seq GlyphPos -> Double
getGlyphsWidth glyphs = getGlyphsMax glyphs - getGlyphsMin glyphs

getTextLinesSize :: Seq TextLine -> Size
getTextLinesSize textLines = size where
  width = maximum (fmap (_sW . _tlSize) textLines)
  height = sum (fmap (_sH . _tlSize) textLines)
  size
    | Seq.null textLines = def
    | otherwise = Size width height

moveTextLines :: Double -> Double -> Seq TextLine -> Seq TextLine
moveTextLines offsetX offsetY textLines = newTextLines where
  moveTextLine tl = tl
    & L.rect . L.x +~ offsetX
    & L.rect . L.y +~ offsetY
  newTextLines = fmap moveTextLine textLines

isSpaceGroup :: Seq GlyphPos -> Bool
isSpaceGroup Empty = False
isSpaceGroup (g :<| gs) = isSpace (_glpGlyph g)

splitGroups :: Seq GlyphPos -> Seq GlyphGroup
splitGroups Empty = Empty
splitGroups glyphs = group <| splitGroups rest where
  g :<| gs = glyphs
  groupWordFn = not . isWordDelimiter . _glpGlyph
  (group, rest)
    | isWordDelimiter (_glpGlyph g) = (Seq.singleton g, gs)
    | otherwise = Seq.spanl groupWordFn glyphs

resetGlyphs :: Seq GlyphPos -> Seq GlyphPos
resetGlyphs Empty = Empty
resetGlyphs gs@(g :<| _) = resetGlyphsPos gs (_glpXMin g)

resetGlyphsPos :: Seq GlyphPos -> Double -> Seq GlyphPos
resetGlyphsPos Empty _ = Empty
resetGlyphsPos (g :<| gs) offset = newG <| resetGlyphsPos gs offset where
  newG = g {
    _glpXMin = _glpXMin g - offset,
    _glpXMax = _glpXMax g - offset
  }

trimGlyphs :: Seq GlyphPos -> Seq GlyphPos
trimGlyphs glyphs = newGlyphs where
  isSpaceGlyph g = _glpGlyph g == ' '
  newGlyphs = Seq.dropWhileL isSpaceGlyph $ Seq.dropWhileR isSpaceGlyph glyphs

isWordDelimiter :: Char -> Bool
isWordDelimiter = (== ' ')

isSpace :: Char -> Bool
isSpace = (== ' ')