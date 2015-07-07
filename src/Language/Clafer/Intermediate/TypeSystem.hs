{-# LANGUAGE NamedFieldPuns #-}
{-
 Copyright (C) 2015 Michal Antkiewicz <http://gsd.uwaterloo.ca>

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
-}
module Language.Clafer.Intermediate.TypeSystem where

import Language.Clafer.Common
import Language.Clafer.Intermediate.Intclafer hiding (uid)

import Control.Monad (mplus, liftM)
import Data.List (nub)
import Data.Maybe
import Prelude hiding (exp)

--import Debug.Trace

-- | Sing
rootTClafer :: IType
rootTClafer = TClafer ["root"]

-- | Obj
claferTClafer :: IType
claferTClafer = TClafer ["clafer"]

numeric :: IType -> Bool
numeric TInteger = True
numeric TReal    = True
numeric TDouble  = True
numeric _        = False

-- | Get TClafer for a given Clafer
-- can only be called after inheritance resolver
getTClafer :: IClafer -> IType
getTClafer    iClafer' = case _uid iClafer' of
  "root"   -> rootTClafer
  "clafer" -> claferTClafer
  _        -> case _super iClafer' of
    Nothing     -> TClafer [ _uid iClafer']
    Just super' -> fromJust $ _iType super'

-- | Get TClafer for a given Clafer by its UID
-- can only be called after inheritance resolver
getTClaferByUID :: UIDIClaferMap -> UID -> Maybe IType
getTClaferByUID    uidIClaferMap'   uid' = case uid' of
  "root"   -> Just $ rootTClafer
  "clafer" -> Just $ claferTClafer
  _        -> getTClafer <$> findIClafer uidIClaferMap' uid'

-- | Get TClafer for a given Clafer by its UID
-- can only be called after inheritance resolver
getTClaferFromIExp :: UIDIClaferMap -> IExp -> Maybe IType
getTClaferFromIExp    uidIClaferMap'   (IClaferId _ uid' _ _) = getTClaferByUID uidIClaferMap' uid'
getTClaferFromIExp    _                (IInt _)               = Just TInteger
getTClaferFromIExp    _                (IReal _)              = Just TReal
getTClaferFromIExp    _                (IDouble _)            = Just TDouble
getTClaferFromIExp    _                (IStr _)               = Just TString
getTClaferFromIExp    _                _                      = Nothing

-- | Get TMap for a given reference Clafer. Nothing for non-reference clafers.
-- can only be called after inheritance resolver
getTMap :: IClafer -> Maybe IType
getTMap    iClafer' = case _uid iClafer' of
  "root"   -> Nothing
  "clafer" -> Nothing
  _        -> _iType =<< _ref <$> _reference iClafer'

-- | Get TClafer for a given Clafer by its UID
-- can only be called after inheritance resolver
getTMapByUID :: UIDIClaferMap -> UID -> Maybe IType
getTMapByUID    uidIClaferMap'   uid' = case uid' of
  "root"   -> Nothing
  "clafer" -> Nothing
  _        -> getTMap =<< findIClafer uidIClaferMap' uid'


hierarchy :: (Monad m) => UIDIClaferMap -> UID -> m [IClafer]
hierarchy uidIClaferMap' uid' = (case findIClafer uidIClaferMap' uid' of
      Nothing -> fail $ "TypeSystem.hierarchy: clafer " ++ uid' ++ "not found!"
      Just clafer -> return $ findHierarchy getSuper uidIClaferMap' clafer)

hierarchyMap :: (Monad m) => UIDIClaferMap -> (IClafer -> a) -> UID -> m [a]
hierarchyMap uidIClaferMap' f c = (case findIClafer uidIClaferMap' c of
      Nothing -> fail $ "TypeSystem.hierarchyMap: clafer " ++ c ++ "not found!"
      Just clafer -> return $ mapHierarchy f getSuper uidIClaferMap' clafer)


{- ---------------------------------------
 - Sums, Intersections, and Compositions -
 --------------------------------------- -}

unionType :: IType -> [String]
unionType TString  = [stringType]
unionType TReal    = [realType]
unionType TDouble  = [doubleType]
unionType TInteger = [integerType]
unionType (TClafer u) = u
unionType (TUnion types) = concatMap unionType types
unionType TBoolean = error $ "TypeSystem.unionType: cannot union TBoolean"
unionType tm@(TMap _ _) = error $ "TypeSystem.unionType: cannot union TMap: '" ++ show tm ++ "'"

fromUnionType :: [String] -> Maybe IType
fromUnionType u =
    case nub $ u of
        ["string"]  -> return TString
        ["integer"] -> return TInteger
        ["int"]     -> return TInteger
        ["double"]  -> return TDouble
        ["real"]    -> return TReal
        []          -> Nothing
        u'          -> return $ TClafer u'

-- | Union the two given types
-- >>> TString +++ TString
-- TString
-- >>> TUnion [TString] +++ TString
-- TUnion {_un = [TString]}
-- >>> TUnion [TString] +++ TInteger
-- TUnion {_un = [TInteger,TString]}
-- >>> TUnion [TString] +++ TUnion[TInteger]
-- TUnion {_un = [TString,TInteger]}
(+++) :: IType -> IType -> IType
TString        +++ TString        = TString
TReal          +++ TReal          = TReal
TDouble        +++ TDouble        = TDouble
TInteger       +++ TInteger       = TInteger
(TClafer u1)   +++ (TClafer u2)   = (TClafer $ nub $ u1 ++ u2)
(TMap so1 ta1) +++ (TMap so2 ta2) = (TMap (so1 +++ so2) (ta1 +++ ta2))
(TUnion un1)   +++ (TUnion un2)   = (TUnion $ nub $ un1 ++ un2)
(TUnion un1)   +++ t2             = (TUnion $ nub $ t2:un1)
t1             +++ (TUnion un2)   = (TUnion $ nub $ t1:un2)
t1             +++ t2              = {-trace ("TypeSystem.(+++): cannot union incompatible types: '"
                                ++ show t1
                                ++ "'' and '"
                                ++ show t2
                                ++ "'") -}
                              TUnion [t1, t2]
-- original version
-- (+++) :: IType -> IType -> IType
-- t1 +++ t2 = fromJust $ fromUnionType $ unionType t1 ++ unionType t2

intersection :: Monad m => UIDIClaferMap -> IType -> IType -> m (Maybe IType)
intersection _              TBoolean        TBoolean      = return $ Just TBoolean
intersection _              TString         TString       = return $ Just TString
intersection _              TReal           TReal         = return $ Just TReal
intersection _              TReal           TDouble       = return $ Just TReal
intersection _              TDouble         TReal         = return $ Just TReal
intersection _              TReal           TInteger      = return $ Just TReal
intersection _              TInteger        TReal         = return $ Just TReal
intersection _              TDouble         TDouble       = return $ Just TDouble
intersection _              TDouble         TInteger      = return $ Just TDouble
intersection _              TInteger        TDouble       = return $ Just TDouble
intersection _              TInteger        TInteger      = return $ Just TInteger
intersection uidIClaferMap' t@(TClafer ut1) (TClafer ut2) = if ut1 == ut2
  then return $ Just t
  else do
    h1 <- (mapM (hierarchyMap uidIClaferMap' _uid) ut1)
    h2 <- (mapM (hierarchyMap uidIClaferMap' _uid) ut2)
    return $ fromUnionType $ catMaybes [contains (head u1) u2 `mplus` contains (head u2) u1 | u1 <- h1, u2 <- h2 ]
  where
  contains i is = if i `elem` is then Just i else Nothing
intersection uidIClaferMap' ot1@(TClafer _) (TMap _ ta2)    = intersection uidIClaferMap' ot1 ta2
intersection uidIClaferMap' (TMap _ ta1)    ot2@(TClafer _) = intersection uidIClaferMap' ta1 ot2
intersection uidIClaferMap' (TMap _ ta1)    (TMap _ ta2)    = composition uidIClaferMap' ta1 ta2
intersection _              _               _               = do
  -- traceM $ "(DEBUG) TypeSystem.intersection: cannot intersect incompatible types: '"
  --      ++ show t1
  --      ++ "'' and '"
  --      ++ show t2
  --      ++ "'"
  return Nothing

-- old version
-- intersection :: Monad m => UIDIClaferMap -> IType -> IType -> m (Maybe IType)
-- intersection uidIClaferMap' t1 t2 = do
--   h1 <- (mapM (hierarchyMap uidIClaferMap' _uid) $ unionType t1)
--   h2 <- (mapM (hierarchyMap uidIClaferMap' _uid) $ unionType t2)
--   return $ fromUnionType $ catMaybes [contains (head u1) u2 `mplus` contains (head u2) u1 | u1 <- h1, u2 <- h2 ]
--   where
--   contains i is = if i `elem` is then Just i else Nothing



-- | Compute the type of sequential composition of two types
composition :: Monad m => UIDIClaferMap -> IType -> IType -> m (Maybe IType)
composition uidIClaferMap' (TMap so1 ta1) (TMap so2 ta2) = do
    -- check whether we can compose?
    _ <- intersection uidIClaferMap' ta1 so2
    return $ Just $ TMap so1 ta2
composition uidIClaferMap' ot1          (TMap so2 ta2) = do
    ot1' <- intersection uidIClaferMap' ot1 so2
    return $ TMap <$> ot1' <*> Just ta2
composition uidIClaferMap' (TMap so1 ta1) ot2          = do
    ot2' <- intersection uidIClaferMap' ta1 ot2
    return $ TMap so1 <$> ot2'
composition _              _            _            = do
  -- traceM $ "(DEBUG) ResolverType.composition: cannot compose incompatible types: '"
  --      ++ show t1
  --      ++ "'' and '"
  --      ++ show t2
  --      ++ "'"
  return Nothing


closure :: Monad m => UIDIClaferMap -> [String] -> m [String]
closure uidIClaferMap' ut = concat `liftM` mapM (hierarchyMap uidIClaferMap' _uid) ut


{- Coersions -}

coerce :: IType -> IType -> IType
-- basic coersions
coerce TReal TReal       = TReal
coerce TReal TInteger    = TReal
coerce TInteger TReal    = TReal
coerce TReal TDouble     = TReal
coerce TDouble TReal     = TReal
coerce TDouble TDouble   = TDouble
coerce TDouble TInteger  = TDouble
coerce TInteger TDouble  = TDouble
coerce TInteger TInteger = TInteger
-- reduce complex types to simple ones
coerce (TMap s1 t1) t2           = TMap s1 $ coerce t1 t2
coerce t1           (TMap s2 t2) = TMap s2 $ coerce t1 t2
coerce x y = error $ "TypeSystem.coerce: Cannot coerce not numeric: " ++ show x ++ " and " ++ show y

{- Note about intersections and unions

Refinement Intersections
========================

http://cstheory.stackexchange.com/questions/20536/what-are-the-practical-issues-with-intersection-and-union-types
"the intersection/union of two types can be formed only if they refine the same archetype"

In Clafer, that means that for
abstract Person
abstract Student : Person
Alice : Student   -- AT = TClafer [ Alice, Student, Person ]
Bob : Person      -- BT = TClafer [ Bob, Person ]

then

AT +++ BT = TClafer [ Person ]
AT *** BT = TClafer [ Person ]


Unrestricted Intersections
==========================

http://www.cs.cmu.edu/~joshuad/papers/intcomp/Dunfield12_elaboration.pdf

Subtyping Union Types
http://www.pps.univ-paris-diderot.fr/~vouillon/publi/subtyping-csl.pdf
-}
