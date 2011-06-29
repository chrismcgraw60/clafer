module Generator.Alloy where

import Data.Char
import Data.List
import Data.Maybe
import Data.Function

import Common
import Front.Absclafer
import Intermediate.Intclafer

genModule :: IModule -> Result
genModule declarations = header ++ (declarations >>= genDeclaration)

-- TODO: header depends on the use of ints/strings
header = unlines
    [ "pred show {}"
    , "run  show for 1"
    , ""
{-    , concat ["fun ", children, "(p : ",  baseClafer, ") : set ", baseClafer,
              "{p.~", parent, " - p}"] -}
    ]


valField = "val"


genDeclaration :: IDeclaration -> Result
genDeclaration x = case x of
  IClaferDecl clafer  -> genClafer Nothing clafer
  IConstDecl lexp  -> mkFact $ genLExp lexp


mkFact xs = concat ["fact ", mkSet xs, "\n"]

mkSet xs = concat ["{ ", xs, " }"]

showSet delim xs = showSet' delim $ filterNull xs
  where
  showSet' _ []     = "{}"
  showSet' delim xs = mkSet $ intercalate delim xs


-- optimization: of only boolean parents, then set card is known
genClafer :: Maybe IClafer -> IClafer -> Result
genClafer parent clafer
  | isRef clafer = ""
  | otherwise    = (unlines $ filterNull
                   [claferDecl clafer
                   , showSet "\n, " $ genRelations parent clafer
                   , showSet "\n  " $ genConstraints parent clafer
                   ]) ++ children
  where
  children = concat $ filterNull $ map (genClafer $ Just clafer) $
             getSubclafers $ elements clafer
             

claferDecl clafer = concat [genAbstract $ isAbstract clafer, "sig ",
  uid clafer, genExtends $ super clafer]
  where
  genAbstract isAbstract = if isAbstract then "abstract " else ""
  genExtends (ISuper False [SExpIdent (Ident "clafer")]) = ""
  genExtends (ISuper False [SExpIdent (Ident id)]) = " extends " ++ id
  genExtends _ = ""

-- -----------------------------------------------------------------------------
-- overlapping inheritance is a new clafer with val (unlike only relation)
-- relations: overlapping inheritance (val rel), children
-- adds parent relation
genRelations parent clafer = genParentRel parent : ref :
  (map mkRel $ getSubclafers $ elements clafer)
  where
  ref = if isOverlapping $ super clafer then
          genRel "ref" clafer $ refType clafer
        else ""
  mkRel c = genRel (genRelName $ uid c) c $ (if isRef c then refType else uid) c


genRelName name = "r_" ++ name


genRel name clafer rType = genAlloyRel name (genCardCrude $ card clafer) rType'
  where
  rType' = if rType `elem` [intType, integerType, strType] then "Int" else rType

-- optimization: direct ref to Int attribute (no new clafer)
-- reference clafers as relations


isRef clafer = (null $ elements clafer) && (isOverlapping $ super clafer)


genAlloyRel name card rType = concat [name, " : ", card, " ", rType]


genParentRel pClafer = maybe "" (genAlloyRel parent "one" . uid) pClafer

refType c = intercalate " + " $ map (genType.getTarget) $ supers $ super c


getTarget :: SExp -> SExp
getTarget x = case x of
  SExpJoin sexp0 sexp  -> sexp
  _ -> x


-- TODO: implement type recognition for relations in alloy, and relations in alloy constraints
genType :: SExp -> Result
genType x = case x of
  SExpUnion sexp0 sexp -> genS sexp0 "+" sexp
  SExpIntersection sexp0 sexp  -> genS sexp0 "&" sexp
  SExpDomain sexp0 sexp  -> genS sexp0 "<:" sexp
  SExpRange sexp0 sexp  -> genS sexp0 ":>" sexp
  SExpJoin sexp0 sexp  -> genS sexp0 "." sexp
  SExpIdent ident -> transIdent ident
  where
  genS = genBinOp genType

-- -----------------------------------------------------------------------------
-- constraints
-- user constraints + parent + TODO: group constraints + reference
genConstraints parent clafer = genParentConst parent clafer : constraints
  where
  constraints = mapMaybe genConst $ elements clafer
  genConst x = case x of
    ISubconstraint lexp  -> Just $ genLExp lexp
    _ -> Nothing

-- optimization: if only boolean features then the parent is unique
genParentConst pClafer clafer = maybe ""
  (const $ concat [parent, " = ", genRelName $ uid clafer, ".this"]) pClafer


-- TODO: when refering to top level declarations don't use names of relations
-- -----------------------------------------------------------------------------
genGCard element gcard = genInterval element  $ interval $ fromJust gcard


genCard element card = genInterval element $ fromJust card


genCardCrude card = genIntervalCrude $ fromJust card


genIntervalCrude x = case x of
  (1, ExIntegerNum 1) -> "one"
  (0, ExIntegerNum 1) -> "lone"
  (1, ExIntegerAst)   -> "some"
  _                   -> "set"


genInterval :: String -> Interval -> Result
genInterval element x = case x of
  (1, ExIntegerNum 1) -> "one"
  (0, ExIntegerNum 1) -> "lone"
  (1, ExIntegerAst)   -> "some"
  (0, ExIntegerAst)   -> "set"
  (n, exinteger)  ->
    s1 ++ (if null s1 || null s2 then "" else " and") ++ s2
    where
    s1 = if n == 0 then "" else concat [show n, " <= #",  element]
    s2 = genExInteger element exinteger


genExInteger :: String -> ExInteger -> Result
genExInteger element x = case x of
  ExIntegerAst  -> ""
  ExIntegerNum n  -> concat [" #", element, " <= ", show n]


-- -----------------------------------------------------------------------------
-- Generate code for logical expressions

-- TODO: join with relations

genLExp :: ILExp -> Result
genLExp x = case x of
  IEIff lexp0 lexp  -> genL lexp0 " <=> " lexp
  IEImpliesElse lexp0 lexp Nothing  -> genL lexp0 " => " lexp
  IEImpliesElse lexp0 lexp1 (Just lexp)  -> concat 
    [genLExp (IEImpliesElse lexp0 lexp1 Nothing), " else (", genLExp lexp, ")"]
  IEOr lexp0 lexp  -> genL lexp0 " or " lexp
  IEXor lexp0 lexp  -> genLExp $ IENeg $ IEIff lexp0 lexp
  IEAnd lexp0 lexp  -> genL lexp0 " && " lexp
  IENeg lexp  -> "not ("  ++ genLExp lexp ++ ")"
  IETerm term  -> genTerm term
  where
  genL = genBinOp genLExp


genTerm :: ITerm -> Result
genTerm x = case x of
  ITermCmpExp cmpexp  -> genCmpExp cmpexp
  ITermQuantSet quant sexp -> genQuant quant ++ " "  ++ genSExp sexp
  ITermQuantDeclExp decls lexp -> concat
    [intercalate "| " $ map genDecl decls, " | ",  genLExp lexp]


genCmpExp :: CmpExp -> Result
genCmpExp x = case x of
  ELt exp0 exp  -> genCmp exp0 " < " exp
  EGt exp0 exp  -> genCmp exp0 " > " exp
  EEq exp0 exp  -> genCmp exp0 " = " exp
  EREq exp0 exp  -> genCmp exp0 " = " exp
  ELte exp0 exp  -> genCmp exp0 " =< " exp
  EGte exp0 exp  -> genCmp exp0 " >= " exp
  ENeq exp0 exp  -> genCmp exp0 " != " exp
  ERNeq exp0 exp  -> genCmp exp0 " != " exp
  EIn exp0 exp  -> genCmp exp0 " in " exp
  ENin exp0 exp  -> genCmp exp0 " not in " exp
  where
  genCmp = genBinOp genExp


genSExp :: SExp -> Result
genSExp x = genSExp' x True

-- TODO: implement type recognition for relations in alloy, and relations in alloy constraints
genSExp' :: SExp -> Bool -> Result
genSExp' x isFirst = case x of
  SExpUnion sexp0 sexp -> genS sexp0 "+" sexp
  SExpIntersection sexp0 sexp  -> genS sexp0 "&" sexp
  SExpDomain sexp0 sexp  -> genS sexp0 "<:" sexp
  SExpRange sexp0 sexp  -> genS sexp0 ":>" sexp
  SExpJoin sexp0 sexp  -> intercalate "."
    [brArg (flip genSExp' isFirst) sexp0, brArg (flip genSExp' False) sexp]
  SExpIdent ident -> (if isFirst then id else genRelName "") ++ transIdent ident
    where
    id = if transIdent ident `elem` [this, parent, strType, intType, integerType, children] then "" else genRelName ""
  where
  genS = genBinOp (flip genSExp' isFirst)



genBinOp f x op y = ((lurry (intercalate op)) `on` (brArg f)) x y


brArg f arg = "(" ++ f arg ++ ")"


genExp :: Exp -> Result
genExp x = case x of
  ESetExp sexp  -> genSExp sexp
  ENumExp aexp -> genAExp aexp
  EStrExp strexp -> error "analyzed"


genQuant :: Quant -> Result
genQuant x = case x of
  QuantNo   -> "no"
  QuantLone -> "lone"
  QuantOne  -> "one"
  QuantSome -> "some"


genExQuant :: ExQuant -> Result
genExQuant x = case x of
  ExQuantAll -> "all"
  ExQuant quant -> genQuant quant


genDecl :: Decl -> Result
genDecl x = case x of
  Decl exquant disj locids sexp -> concat [genExQuant exquant, " ",
    genDisj disj, " ",
    intercalate ", " $ map genLocId locids, " : ", genSExp sexp]


genDisj :: Disj -> Result
genDisj x = case x of
  DisjEmpty -> ""
  Disj -> "disj"


genLocId :: LocId -> Result
genLocId x = case x of
   LocIdIdent ident -> transIdent ident


genAExp :: AExp -> Result
genAExp x = case x of
  EAdd aexp0 aexp -> genArith aexp0 "+" aexp
  ESub aexp0 aexp -> genArith aexp0 "-" aexp
  EMul aexp0 aexp -> genArith aexp0 "*" aexp
  EUmn aexp -> "-" ++ brArg genAExp aexp
  ECSetExp sexp -> "#" ++ brArg genSExp sexp
  EInt n    -> show n
  where
  genArith = genBinOp genAExp