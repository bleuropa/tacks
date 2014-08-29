module Render.All where

import Core (..)
import Geo (..)
import Game (..)
import String
import Text

import Render.Utils (..)
import Render.Race (..)
import Render.Controls (..)

renderAll : (Int,Int) -> GameState -> Element
renderAll (w,h) gameState =
  let dims = floatify (w,h)
      (w',h') = dims
      relativeForms = renderRelative gameState
      absoluteForms = renderAbsolute gameState dims      
      bg = rect w' h' |> filled colors.sand
  in  layers [collage w h [bg, group [relativeForms, absoluteForms]]]
