{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, BangPatterns #-}

module Main where

import Text.Printf (printf)
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import Network.Socket hiding (recv, send)
import Network.Socket.ByteString (recv, sendAll)
import Numeric (readHex)
import Data.Maybe (mapMaybe, fromMaybe)
import Data.List (isPrefixOf, isSuffixOf, nub, foldl')
import System.IO (stderr, hFlush, hPutStr)
import Data.Word8 (isSpace)

newtype PacketLine = PacketLine B.ByteString deriving (Show)

data Url = Url {
    protocol :: String,
    address  :: String,
    name     :: String
} deriving (Show, Eq)

splitOn :: String -> Char -> [String]
splitOn str delim = go str "" []
  where
    go [] accPart accList = accList ++ [accPart]  
    go (x:xs) accPart accList
      | x == delim = go xs "" (accList ++ [accPart])  
      | otherwise  = go xs (accPart ++ [x]) accList


parseString :: String -> Url
parseString url = 
  let parts = foldr removeEmpty [] (splitOn url '/')
  in case parts of
    [protoStr, addrStr, nameStr] ->
      let proto = takeWhile (/= ':') protoStr
      in Url proto addrStr nameStr
    _ -> error "invalid url"
  where
    removeEmpty str acc
      | str == ""  = acc
      | otherwise  = str : acc

withConnection :: HostName -> ServiceName -> (Socket -> IO b) -> IO b
withConnection host port consumer = do
    sock <- openConnection host port
    r <- consumer sock
    close sock
    return r

openConnection :: HostName -> ServiceName -> IO Socket
openConnection host port = do
    addrinfos <- getAddrInfo Nothing (Just host) (Just port)
    let serveraddr = head addrinfos
    sock <- socket (addrFamily serveraddr) Stream defaultProtocol
    connect sock (addrAddress serveraddr)
    return sock

readPacketLine :: Socket -> IO (Maybe B.ByteString)
readPacketLine sock = do
    len <- readFully mempty 4
    if B.null len then return Nothing else
      case readHex (C.unpack len) of
        ((l,_):_) | l > 4 -> Just <$> readFully mempty (l - 4)
        ((0,_):_)         -> return Nothing
        _                 -> return Nothing
  where
    readFully acc expected = do
        chunk <- recv sock expected
        let acc' = acc <> chunk
        if B.length acc' < expected && not (B.null chunk)
           then readFully acc' (expected - B.length chunk)
           else return acc'

send :: Socket -> String -> IO ()
send sock msg = sendAll sock $ C.pack msg

receive :: Socket -> IO B.ByteString
receive sock = go mempty
  where
    go acc = do
        mline <- readPacketLine sock
        case mline of
          Nothing   -> return acc
          Just line -> go (acc <> line)

pktLine :: String -> String
pktLine s = let len = length s + 4
                hex = C.unpack $ C.pack $ printf "%04x" len
            in hex ++ s

flushPkt :: String
flushPkt = "0000"

gitProtoRequest :: String -> String -> String
gitProtoRequest host repo =
    pktLine ("git-upload-pack /" ++ repo ++ "\0host=" ++ host ++ "\0")

parsePacket :: L.ByteString -> [PacketLine]
parsePacket = parseLines . L.toChunks
  where
    parseLines [] = []
    parseLines (x:xs)
      | B.null x = []
      | otherwise = PacketLine x : parseLines xs

toRef :: PacketLine -> Maybe (B.ByteString, B.ByteString)
toRef (PacketLine line) =
  let (obj, rest) = B.break isSpace line
      rest' = B.dropWhile isSpace rest
      (ref, _) = B.break (== 0) rest'  -- split on null byte
  in if B.null obj || B.null ref then Nothing else Just (obj, ref)

main :: IO ()
main = withConnection "127.0.0.1" "9418" $ \sock -> do
    let payload = gitProtoRequest "127.0.0.1" "zellij.git"
    send sock payload
    send sock flushPkt
    response <- receive sock
    let refs = mapMaybe toRef (parsePacket $ L.fromChunks [response])
    putStrLn "Refs advertised by server:"
    mapM_ (\(obj, ref) -> C.putStrLn (obj <> " " <> ref)) refs

