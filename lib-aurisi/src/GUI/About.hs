{-# LANGUAGE OverloadedStrings
    , TemplateHaskell 
    , QuasiQuotes
    , ForeignFunctionInterface     
#-}
module GUI.About
  ( createAboutDialog
  )
where

import           RIO
import           GI.Gtk                        as Gtk

import           Data.Text                     as T

import           Version

import           Data.FileEmbed
import           GUI.Logo


license :: Text
license = T.pack $(makeRelativeToProject "LICENSE" >>= embedStringFile)



createAboutDialog :: IO Gtk.AboutDialog
createAboutDialog = do
    -- setup about dialog
  aboutDialog <- aboutDialogNew

  logo'       <- getLogoPixbuf 150 150

  let attribs1 = 
        [ aboutDialogProgramName := ("AURISi" :: Text)
        , aboutDialogVersion := aurisVersion
        , aboutDialogCopyright := ("(C) by Michael Oswald" :: Text)
        , aboutDialogComments
          := ("AURIS: an open source mission control system.\n\n" :: Text)
        , aboutDialogAuthors
          := ["Michael Oswald (michael.oswald@onikudaki.net)" :: Text,
          "Paolo Varonelli", "Matthias Putz", "Max Taldykin", "Adam Bratschi-Kaye", "Jan van Brüggen"]
        , aboutDialogLicense := license
        , aboutDialogWrapLicense := True
        ]
      attribs = case logo' of 
          Nothing -> attribs1 
          Just logo -> attribs1 ++ [aboutDialogLogo := logo]

  Gtk.set aboutDialog attribs

  return aboutDialog


