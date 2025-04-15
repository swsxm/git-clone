-- git ls-remote git://127.0.0.1/zellij.git

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

