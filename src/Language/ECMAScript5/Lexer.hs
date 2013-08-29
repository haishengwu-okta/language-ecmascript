{-# LANGUAGE Rank2Types #-}

module Language.ECMAScript5.Lexer where

import Text.Parsec 
import Language.ECMAScript5.Parser.Util
import Language.ECMAScript5.Parser.Unicode
import Language.ECMAScript5.ParserState

import Language.ECMAScript5.Syntax
import Data.Default.Class
import Data.Default.Instances.Base

import Data.Char
import Data.Maybe (fromMaybe)
import Numeric(readDec,readOct,readHex)

import Control.Monad.Identity
import Control.Applicative ((<$>), (<*), (*>), (<*>), (<$))


lexeme :: Show a => Parser a -> Parser a
lexeme p = p <* ws

--7.2

ws :: Parser Bool
ws = many (False <$ whiteSpace <|> False <$ comment <|> True <$ lineTerminator) >>= setNewLineState
  where whiteSpace :: Parser ()
        whiteSpace = forget $ choice [uTAB, uVT, uFF, uSP, uNBSP, uBOM, uUSP]

--7.3
uCRalone :: Parser Char
uCRalone = do uCR <* notFollowedBy uLF

lineTerminator :: Parser ()
lineTerminator = forget (uLF <|> uCR <|> uLS <|> uPS)
lineTerminatorSequence  :: Parser ()
lineTerminatorSequence = forget (uLF <|> uCRalone <|> uLS <|> uPS ) <|> forget uCRLF

--7.4
comment :: Parser String
comment = try multiLineComment <|> try singleLineComment

singleLineCommentChar :: Parser Char
singleLineCommentChar  = notFollowedBy lineTerminator *> noneOf ""

multiLineComment :: Parser String
multiLineComment = 
  do string "/*"
     comment <- concat <$> many insideMultiLineComment
     string "*/"
     modifyState $ modifyComments (MultiLineComment comment:)
     return comment

singleLineComment :: Parser String
singleLineComment = 
  do string "//" 
     comment <- many singleLineCommentChar
     modifyState $ modifyComments (SingleLineComment comment :)
     return comment

insideMultiLineComment :: Parser [Char]
insideMultiLineComment = noAsterisk <|> try asteriskInComment
 where
  noAsterisk =
    stringify $ noneOf "*"
  asteriskInComment =
    (:) <$> char '*' <*> (stringify (noneOf "/*") <|> "" <$ lookAhead (char '*') )

--7.5
--token = identifierName <|> punctuator <|> numericLiteral <|> stringLiteral

--7.6
identifier :: PosParser Expression
identifier = withPos $ do name <- identifierName
                          return $ VarRef def name

identifierName :: PosParser Id
identifierName = lexeme $ withPos $ flip butNot reservedWord $ fmap (Id def) $
                 (:)
                 <$> identifierStart
                 <*> many identifierPart

identifierStart :: Parser Char
identifierStart = unicodeLetter <|> char '$' <|> char '_' <|> unicodeEscape

unicodeEscape :: Parser Char
unicodeEscape = char '\\' >> unicodeEscapeSequence

identifierPart :: Parser Char
identifierPart = identifierStart <|> unicodeCombiningMark <|> unicodeDigit <|>
                 unicodeConnectorPunctuation <|> uZWNJ <|> uZWJ

--7.6.1
reservedWord :: Parser ()
reservedWord = choice [forget keyword, forget futureReservedWord, forget nullLiteral, forget booleanLiteral]

andThenNot :: Show q => Parser a -> Parser q -> Parser a
andThenNot p q = try (p <* notFollowedBy q)

makeKeyword :: String -> Parser Bool
makeKeyword word = try (string word `andThenNot` identifierPart) *> ws

--7.6.1.1
keyword :: Parser Bool
keyword = choice [kbreak, kcase, kcatch, kcontinue, kdebugger, kdefault, kdelete,
                  kdo, kelse, kfinally, kfor, kfunction, kif, kin, kinstanceof, knew,
                  kreturn, kswitch, kthis, kthrow, ktry, ktypeof, kvar, kvoid, kwhile, kwith]

-- ECMAScript keywords
kbreak, kcase, kcatch, kcontinue, kdebugger, kdefault, kdelete,
  kdo, kelse, kfinally, kfor, kfunction, kif, kin, kinstanceof, knew,
  kreturn, kswitch, kthis, kthrow, ktry, ktypeof, kvar, kvoid, kwhile, kwith
  :: Parser Bool
kbreak      = makeKeyword "break"
kcase       = makeKeyword "case"
kcatch      = makeKeyword "catch"
kcontinue   = makeKeyword "continue"
kdebugger   = makeKeyword "debugger"
kdefault    = makeKeyword "default"
kdelete     = makeKeyword "delete"
kdo         = makeKeyword "do"
kelse       = makeKeyword "else"
kfinally    = makeKeyword "finally"
kfor        = makeKeyword "for"
kfunction   = makeKeyword "function"
kif         = makeKeyword "if"
kin         = makeKeyword "in"
kinstanceof = makeKeyword "instanceof"
knew        = makeKeyword "new"
kreturn     = makeKeyword "return"
kswitch     = makeKeyword "switch"
kthis       = makeKeyword "this"
kthrow      = makeKeyword "throw"
ktry        = makeKeyword "try"
ktypeof     = makeKeyword "typeof"
kvar        = makeKeyword "var"
kvoid       = makeKeyword "void"
kwhile      = makeKeyword "while"
kwith       = makeKeyword "with"

--7.6.1.2
futureReservedWord :: Parser Bool
futureReservedWord = choice [kclass, kconst, kenum, kexport, kextends, kimport, ksuper]

kclass, kconst, kenum, kexport, kextends, kimport, ksuper :: Parser Bool
kclass   = makeKeyword "class"
kconst   = makeKeyword "const"
kenum    = makeKeyword "enum"
kexport  = makeKeyword "export"
kextends = makeKeyword "extends"
kimport  = makeKeyword "import"
ksuper   = makeKeyword "super"

--7.7
punctuator :: Parser ()
punctuator = choice [ passignadd, passignsub, passignmul, passignmod,
                      passignshl, passignshr,
                      passignushr, passignband, passignbor, passignbxor,
                      pshl, pshr, pushr,
                      pleqt, pgeqt,
                      plbrace, prbrace, plparen, prparen, plbracket,
                      prbracket, pdot, psemi, pcomma,
                      plangle, prangle, pseq, peq, psneq, pneq,
                      pplusplus, pminusminus,
                      pplus, pminus, pmul,
                      pand, por,
                      pmod, pband, pbor, pbxor, pnot, pbnot,
                      pquestion, pcolon, passign ]
plbrace :: Parser ()
plbrace = forget $ lexeme $ char '{'
prbrace :: Parser ()
prbrace = forget $ lexeme $ char '}'
plparen :: Parser ()
plparen = forget $ lexeme $ char '('
prparen :: Parser ()
prparen = forget $ lexeme $ char ')'
plbracket :: Parser ()
plbracket = forget $ lexeme $ char '['
prbracket :: Parser ()
prbracket = forget $ lexeme $ char ']'
pdot :: Parser ()
pdot = forget $ lexeme $ char '.'
psemi :: Parser ()
psemi = forget $ lexeme $ char ';'
pcomma :: Parser ()
pcomma = forget $ lexeme $ char ','
plangle :: Parser ()
plangle = lexeme $ char '<' *> notFollowedBy (oneOf "=<")
prangle :: Parser ()
prangle = lexeme $ char '>' *> notFollowedBy (oneOf "=>")
pleqt :: Parser ()
pleqt = forget $ lexeme $ string "<="
pgeqt :: Parser ()
pgeqt = forget $ lexeme $ string ">="
peq :: Parser ()
peq  = forget $ lexeme $ string "==" *> notFollowedBy (char '=')
pneq :: Parser ()
pneq = forget $ lexeme $ string "!=" *> notFollowedBy (char '=')
pseq :: Parser ()
pseq = forget $ lexeme $ string "==="
psneq :: Parser ()
psneq = forget $ lexeme $ string "!=="
pplus :: Parser ()
pplus = forget $ lexeme $ do char '+' *> notFollowedBy (oneOf "=+")
pminus :: Parser ()
pminus = forget $ lexeme $ do char '-' *> notFollowedBy (oneOf "=-")
pmul :: Parser ()
pmul = forget $ lexeme $ do char '*' *> notFollowedBy (char '=')
pmod :: Parser ()
pmod = forget $ lexeme $ do char '%' *> notFollowedBy (char '=')
pplusplus :: Parser ()
pplusplus = forget $ lexeme $ string "++"
pminusminus :: Parser ()
pminusminus = forget $ lexeme $ string "--"
pshl :: Parser ()
pshl = forget $ lexeme $ string "<<" *> notFollowedBy (char '=')
pshr :: Parser ()
pshr = forget $ lexeme $ string ">>" *> notFollowedBy (oneOf ">=")
pushr :: Parser ()
pushr = forget $ lexeme $ string ">>>" *> notFollowedBy (char '=')
pband :: Parser ()
pband = forget $ lexeme $ do char '&' *> notFollowedBy (oneOf "&=")
pbor :: Parser ()
pbor = forget $ lexeme $ do char '|' *> notFollowedBy (oneOf "|=")
pbxor :: Parser ()
pbxor = forget $ lexeme $ do char '^' *> notFollowedBy (char '=')
pnot :: Parser ()
pnot = forget $ lexeme $ do char '!' *> notFollowedBy (char '=')
pbnot :: Parser ()
pbnot = forget $ lexeme $ char '~'
pand :: Parser ()
pand = forget $ lexeme $ string "&&"
por :: Parser ()
por = forget $ lexeme $ string "||"
pquestion :: Parser ()
pquestion = forget $ lexeme $ char '?'
pcolon :: Parser ()
pcolon = forget $ lexeme $ char ':'
passign :: Parser ()
passign = lexeme $ char '=' *> notFollowedBy (char '=')
passignadd :: Parser ()
passignadd = forget $ lexeme $ try (string "+=")
passignsub :: Parser ()
passignsub = forget $ lexeme $ try (string "-=")
passignmul :: Parser ()
passignmul = forget $ lexeme $ try (string "*=")
passignmod :: Parser ()
passignmod = forget $ lexeme $ try (string "%=")
passignshl :: Parser ()
passignshl = forget $ lexeme $ try (string "<<=")
passignshr :: Parser ()
passignshr = forget $ lexeme $ try (string ">>=")
passignushr :: Parser ()
passignushr = forget $ lexeme $ try (string ">>>=")
passignband :: Parser ()
passignband = forget $ lexeme $ try (string "&=")
passignbor :: Parser ()
passignbor = forget $ lexeme $ try (string "|=")
passignbxor :: Parser ()
passignbxor = forget $ lexeme $ try (string "^=")
divPunctuator :: Parser ()
divPunctuator = choice [ passigndiv, pdiv ]

passigndiv :: Parser ()
passigndiv = forget $ lexeme $ try (string "/=")
pdiv :: Parser ()
pdiv = forget $ lexeme $ do char '/' *> notFollowedBy (char '=')

--7.8
literal :: PosParser Expression
literal = choice [nullLiteral, booleanLiteral, numericLiteral, stringLiteral, regularExpressionLiteral]

--7.8.1
nullLiteral :: PosParser Expression
nullLiteral = withPos (makeKeyword "null" >> return (NullLit def))

--7.8.2
booleanLiteral :: PosParser Expression
booleanLiteral = withPos $ BoolLit def
                 <$> (True <$ makeKeyword "true" <|> False <$ makeKeyword "false")

--7.8.3
numericLiteral :: PosParser Expression
numericLiteral = hexIntegerLiteral <|> decimalLiteral

-- Creates a decimal value from a whole, fractional and exponent parts.
mkDecimal :: Integer -> Integer -> Integer -> Integer -> Double
mkDecimal whole frac fracLen exp =
  ((fromInteger whole) + ((fromInteger frac) * (10 ^^ (-fracLen)))) * (10 ^^ exp)

-- Creates an integer value from a whole and exponent parts.
mkInteger :: Integer -> Integer -> Int
mkInteger whole exp = fromInteger $ whole * (10 ^ exp)

decimalLiteral :: PosParser Expression
decimalLiteral = lexeme $ withPos $
  (do whole <- decimalInteger
      mfraclen <- optionMaybe (pdot >> decimalDigitsWithLength)
      mexp  <- optionMaybe exponentPart
      if (mfraclen == Nothing && mexp == Nothing)
        then return $ NumLit def $ Left $ fromInteger whole
        else let (frac, flen) = fromMaybe (0, 0) mfraclen
                 exp          = fromMaybe 0 mexp
             in  return $ NumLit def $ Right $ mkDecimal whole frac flen exp)
  <|>
  (do (frac, flen) <- pdot >> decimalDigitsWithLength
      exp <- option 0 exponentPart
      return $ NumLit def $ Right $ mkDecimal 0 frac flen exp)

decimalDigitsWithLength :: Parser (Integer, Integer)
decimalDigitsWithLength = do digits <- many decimalDigit
                             return $ digits2NumberAndLength digits

digits2NumberAndLength :: [Integer] -> (Integer, Integer)
digits2NumberAndLength is =
  let (_, n, l) = foldr (\d (pow, acc, len) -> (pow*10, acc + d*pow, len+1))
                        (1, 0, 0) is
  in (n, l)

decimalIntegerLiteral :: PosParser Expression
decimalIntegerLiteral = lexeme $ withPos $ decimalInteger >>=
                        \i -> return $ NumLit def $ Left $ fromInteger i

decimalInteger :: Parser Integer
decimalInteger = (char '0' >> return 0)
              <|>(do d  <- nonZeroDecimalDigit
                     ds <- many decimalDigit
                     return $ fst $ digits2NumberAndLength (d:ds))

-- the spec says that decimalDigits should be intead of decimalIntegerLiteral, but that seems like an error
signedInteger :: Parser Integer
signedInteger = (char '+' >> decimalInteger) <|>
                (char '-' >> negate <$> decimalInteger) <|>
                decimalInteger

decimalDigit :: Parser Integer
decimalDigit  = do c <- decimalDigitChar
                   return $ toInteger $ ord c - ord '0'

decimalDigitChar :: Parser Char
decimalDigitChar = rangeChar '0' '9'

nonZeroDecimalDigit :: Parser Integer
nonZeroDecimalDigit  = do c <- rangeChar '1' '9'
                          return $ toInteger $ ord c - ord '0'

--hexDigit = ParsecChar.hexDigit

exponentPart :: Parser Integer
exponentPart = (char 'e' <|> char 'E') >> signedInteger


fromHex digits = do [(hex,"")] <- return $ Numeric.readHex digits
                    return hex

fromDecimal digits = do [(hex,"")] <- return $ Numeric.readDec digits
                        return hex
hexIntegerLiteral :: PosParser Expression
hexIntegerLiteral = lexeme $ withPos $ do
  try (char '0' >> (char 'x' <|> char 'X'))
  digits <- many1 hexDigit
  n <- fromHex digits
  return $ NumLit def $ Left $ fromInteger n

--7.8.4
dblquote :: Parser Char
dblquote = char '"'
quote :: Parser Char
quote = char '\''
backslash :: Parser Char
backslash = char '\\'
inDblQuotes :: Parser a -> Parser a
inDblQuotes x = between dblquote dblquote x
inQuotes :: Parser a -> Parser a
inQuotes x = between quote quote x
inParens :: Parser a -> Parser a
inParens x = between plparen prparen x
inBrackets :: Parser a -> Parser a
inBrackets x = between plbracket prbracket x
inBraces :: Parser a -> Parser a
inBraces x = between plbrace prbrace x

stringLiteral :: PosParser (Expression)
stringLiteral =  lexeme $ withPos $
                 do s <- ((inDblQuotes $ concatM $ many doubleStringCharacter)
                          <|>
                          (inQuotes $ concatM $ many singleStringCharacter))
                    return $ StringLit def s

doubleStringCharacter :: Parser String
doubleStringCharacter =
  stringify ((anyChar `butNot` choice[forget dblquote, forget backslash, lineTerminator])
             <|> backslash *> escapeSequence)
  <|> lineContinuation

singleStringCharacter :: Parser String
singleStringCharacter =
  stringify ((anyChar `butNot` choice[forget quote, forget backslash, forget lineTerminator])
             <|> backslash *> escapeSequence)
  <|> lineContinuation

lineContinuation :: Parser String
lineContinuation = backslash >> lineTerminatorSequence >> return ""

escapeSequence :: Parser Char
escapeSequence = characterEscapeSequence
              <|>(char '0' >> notFollowedBy decimalDigitChar >> return cNUL)
              <|>hexEscapeSequence
              <|>unicodeEscapeSequence

characterEscapeSequence :: Parser Char
characterEscapeSequence = singleEscapeCharacter <|> nonEscapeCharacter

singleEscapeCharacter :: Parser Char
singleEscapeCharacter = choice $ map (\(ch, cod) -> (char ch >> return cod))
                        [('b', cBS), ('t', cHT), ('n', cLF), ('v', cVT),
                         ('f', cFF), ('r', cCR), ('"', '"'), ('\'', '\''),
                         ('\\', '\\')]

nonEscapeCharacter :: Parser Char
nonEscapeCharacter = anyChar `butNot` (forget escapeCharacter <|> lineTerminator)

escapeCharacter :: Parser Char
escapeCharacter = singleEscapeCharacter
               <|>decimalDigitChar
               <|>char 'x'
               <|>char 'u'

hexEscapeSequence :: Parser Char
hexEscapeSequence =  do digits <- (char 'x' >> count 2 hexDigit)
                        hex <- fromHex digits
                        return $ chr hex

unicodeEscapeSequence :: Parser Char
unicodeEscapeSequence = do digits <- char 'u' >> count 4 hexDigit
                           hex <- fromHex digits
                           return $ chr hex

--7.8.5 and 15.10.4.1
regularExpressionLiteral :: PosParser Expression
regularExpressionLiteral =
    lexeme $ withPos $ do
      body <- between pdiv pdiv regularExpressionBody
      (g, i, m) <- regularExpressionFlags
      return $ RegexpLit def body g i m

-- TODO: The spec requires the parser to make sure the body is a valid
-- regular expression; were are not doing it at present.
regularExpressionBody :: Parser String
regularExpressionBody = do c <- regularExpressionFirstChar
                           cs <- concatM regularExpressionChars
                           return (c++cs)

regularExpressionChars :: Parser [String]
regularExpressionChars = many regularExpressionChar

regularExpressionFirstChar :: Parser String
regularExpressionFirstChar =
  choice [
    stringify $ regularExpressionNonTerminator `butNot` oneOf ['*', '\\', '/', '[' ],
    regularExpressionBackslashSequence,
    regularExpressionClass ]

regularExpressionChar :: Parser String
regularExpressionChar =
  choice [
    stringify $ regularExpressionNonTerminator `butNot` oneOf ['\\', '/', '[' ],
    regularExpressionBackslashSequence,
    regularExpressionClass ]

regularExpressionBackslashSequence :: Parser String
regularExpressionBackslashSequence = do c <-char '\\'
                                        e <- regularExpressionNonTerminator
                                        return (c:[e])

regularExpressionNonTerminator :: Parser Char
regularExpressionNonTerminator = anyChar `butNot` lineTerminator

regularExpressionClass :: Parser String
regularExpressionClass = do l <- char '['
                            rc <- concatM $ many regularExpressionClassChar
                            r <- char ']'
                            return (l:(rc++[r]))

regularExpressionClassChar :: Parser String
regularExpressionClassChar =
  stringify (regularExpressionNonTerminator `butNot` oneOf [']', '\\'])
  <|> regularExpressionBackslashSequence

regularExpressionFlags :: Parser (Bool, Bool, Bool) -- g, i, m
regularExpressionFlags = regularExpressionFlags' (False, False, False)

regularExpressionFlags' :: (Bool, Bool, Bool) -> Parser (Bool, Bool, Bool)
regularExpressionFlags' (g, i, m) =
    (char 'g' >> (if not g then regularExpressionFlags' (True, i, m) else unexpected "duplicate 'g' in regular expression flags")) <|>
    (char 'i' >> (if not i then regularExpressionFlags' (g, True, m) else unexpected "duplicate 'i' in regular expression flags")) <|>
    (char 'm' >> (if not m then regularExpressionFlags' (g, i, True) else unexpected "duplicate 'm' in regular expression flags")) <|>
    return (g, i, m)