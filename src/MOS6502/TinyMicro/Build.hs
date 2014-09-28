{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Main where

import Development.KansasLava.Shake.Xilinx
import Development.Shake
import Development.Shake.FilePath
import System.Directory
import System.Console.GetOpt
import System.Exit

import qualified Data.ByteString as BS
import Data.Char (toLower)

import Hardware.KansasLava.Boards.Papilio.Arcade (Model(..))
import Language.KansasLava.VHDL (writeVhdlPrelude)
import MOS6502.TinyMicro.Video (synthesize)
import qualified MOS6502.TinyMicro.Board as Board

data Flag = ImageFile FilePath
          | XilinxRoot FilePath
          | PapilioModel String

mkXilinxConfig :: [Flag] -> IO (XilinxConfig, Model)
mkXilinxConfig flags = do
    xilinxRoot <- case [path | XilinxRoot path <- flags] of
        [] -> return "/home/cactus/prog/fpga/Xilinx/14.2/ISE_DS/ISE/bin/lin64"
        [path] -> return path
        _ -> do
            putStrLn "Conflicting flags: --xilinx"
            exitFailure

    (xilinxPlatform, papilioModel) <- case [model | PapilioModel model <- flags] of
        [] -> do
            putStrLn "Defaulting to Papilio One"
            return ("XC3S500E-VQ100-5", PapilioOne)
        [model] -> return $ case map toLower model of
            "one" -> ("XC3S500E-VQ100-5", PapilioOne)
            "pro" -> ("XC6SLX9-TQG144-2", PapilioPro)
        _ -> do
            putStrLn "Conflicting flags: --papilio"
            exitFailure

    return (XilinxConfig{..}, papilioModel)

main :: IO ()
main = do
    createDirectoryIfMissing True "ise"
    setCurrentDirectory "ise"
    shakeArgsWith shakeOptions flags $ \flags targets -> do
        prog <- case [fileName | ImageFile fileName <- flags] of
            [fileName] -> BS.readFile fileName
            _ -> do
                putStrLn "Missing flag: --image"
                exitFailure

        (xilinxConfig, model) <- mkXilinxConfig flags

        (vhdl, ucf) <- synthesize model modName (Board.board prog)
        return $ Just $ do
            want $ if null targets then [modName <.> "bit"] else targets

            lavaRules modName vhdl ucf
            xilinxRules xilinxConfig modName xaws
  where
    flags = [ Option [] ["image"] (ReqArg (Right . ImageFile) "filename") "ROM image file"
            , Option [] ["xilinx"] (ReqArg (Right . XilinxRoot) "path") "Path to Xilinx toolchain"
            , Option [] ["papilio"] (ReqArg (Right . PapilioModel) "model") "Target Papilio model (One/Pro)"
            ]

    modName = "TinyMicro6502"
    xaws = ["dcm_32_to_50p35"]

lavaRules :: FilePath -> String -> String -> Rules ()
lavaRules modName vhdl ucf = do
    gensrc modName <.> "vhdl" *> \target -> writeFileChanged target vhdl
    gensrc modName <.> "ucf" *> \target -> writeFileChanged target ucf
    gensrc "lava-prelude.vhdl" *> liftIO . writeVhdlPrelude
  where
    gensrc f = "gensrc" </> f
