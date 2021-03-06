{-# OPTIONS_GHC -Wno-incomplete-patterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE LambdaCase #-}
module Language.Shape.Stlc.Model where

import Data.Map (Map, lookup, fromList, union, singleton, unions)
import Data.Symbol
import Language.Shape.Stlc.Syntax
import Prelude hiding (lookup)
import System.Directory.Internal.Prelude (newEmptyMVar)
import Data.Maybe

data TypeChange = TypeReplace Type | NoChange | ArrowChange [InputChange] TypeChange
-- data BaseTypeChange = TypeReplace Type | NoChange
data InputChange = Change TypeChange Int | Insert

-- Example:
-- (A,B,C)->D
-- (A,C,?)->D
-- ArrowChange [Change NoChange 0, Change NoChange 2, Insert] NoChange

data VarChange = VariableTypeChange TypeChange | VariableDeletion

data ConstructorChange = CtrChange InputChange Int | CtrInsert
data DataChange = DataTypeDeletion | DataTypeChange [ConstructorChange]

type Changes = (Map Id VarChange, Map Id DataChange)

-- Why arent these basic function in haskell's standard library?
deleteAt :: [a] -> Int -> [a]
deleteAt xs i = take i xs ++ drop (i + 1) xs

insertAt :: [a] -> Int -> a -> [a]
insertAt xs i x = take i xs ++ [x] ++ drop i xs

applyAt :: [a] -> Int -> (a -> a) -> [a]
applyAt xs i f = take i xs ++ [f (xs !! i)] ++ drop (i + 1) xs

chType :: Changes -> TypeChange -> Type -> Type
chType gamma c t = 
  let chTypeImpl :: TypeChange -> Type -> Type
      chTypeImpl NoChange t = t
      chTypeImpl (TypeReplace t2) t1 = t2
      chTypeImpl (ArrowChange ics out) (ArrowType as b)
        = ArrowType (map mapper ics) bNew
        where bNew = case out of
                TypeReplace (BaseType t) -> t
                NoChange -> b
                _ -> error "base type is not arrow type"
              mapper :: InputChange -> (Name, Type)
              mapper (Change tc n) = (fst $ as !! n , chTypeImpl tc (snd $ as !! n))
              mapper Insert = ("_" , BaseType (HoleType (newSymbol ()) []))
      chTypeImpl (ArrowChange _ _) (BaseType bt) = error "Can't ArrowChange a base type"
  in searchType gamma (chTypeImpl c t)

searchType :: Changes -> Type -> Type
searchType gamma (ArrowType ins out)
  = ArrowType (map (\(x,t) -> (x, searchType gamma t)) ins) (searchBaseType gamma out)
searchType gamma (BaseType bt) = BaseType (searchBaseType gamma bt)

searchBaseType :: Changes -> BaseType -> BaseType
searchBaseType gamma (DataType x) = case lookup x (snd gamma) of
  Nothing -> DataType x
  Just dc -> case dc of
    DataTypeDeletion -> HoleType (newSymbol ()) []
    (DataTypeChange dcc) -> DataType x
searchBaseType gamma (HoleType sym syms) = _w1a -- remove deleted types from weakening?

chArgs :: Changes -> [InputChange] -> [Term] -> [Term]
chArgs gamma c args = map mapper c
  where mapper :: InputChange -> Term
        mapper (Change tc n) = searchTerm gamma $ chTerm gamma tc (args !! n)
        mapper Insert = HoleTerm []

searchArgs :: Changes -> [Term] -> [Term]
searchArgs gamma = map (searchTerm gamma)

chTerm :: Changes -> TypeChange -> Term -> Term
-- TODO: need to thread context and type through all these function in order to deal with this undefined.
chTerm gamma (TypeReplace ty) t = HoleTerm undefined {-t but remove lambdas-}
chTerm gamma NoChange t = searchTerm gamma t
chTerm gamma (ArrowChange ics tc) (LambdaTerm syms bl)
  = LambdaTerm (map symMapper ics)
    (chBlock (fst gamma `union` newChanges, snd gamma) tc bl)
  where symMapper :: InputChange -> Id
        symMapper (Change tc' n) = syms !! n
        symMapper Insert = newSymbol () -- In order for changes to be in gamma, Insert will need info about the new type.
        changeMapper :: InputChange -> Map Id VarChange
        changeMapper (Change tc' n) = singleton (syms !! n) VariableDeletion
        changeMapper Insert = mempty
        newChanges :: Map Id VarChange
        newChanges = unions (map changeMapper ics)
chTerm gamma (ArrowChange ics tc) _ = error "only a lambda should be an arrow type"

termToNeutral :: Changes -> Term -> Maybe NeutralTerm
-- For now, just forgets everything that was in the definitions section of the block. TODO: figure out what it should do.
termToNeutral gamma (LambdaTerm syms (Block _ t))
  -- = termToNeutral gamma (searchTerm (union deletions (fst gamma), (snd gamma)) t)
  = searchNeutral (union deletions (fst gamma), (snd gamma)) t
    where deletions :: Map Id VarChange
          deletions = fromList (map (\x -> (x, VariableDeletion)) syms)
termToNeutral gamma (HoleTerm tes) = Nothing
termToNeutral gamma (NeutralTerm nt) = Just nt

blockToNeutral :: Changes -> Block -> Maybe NeutralTerm
-- Again, for now, just forgets everything that was in the definitions section of the block. TODO: figure out what it should do.
blockToNeutral gamma (Block des t) = termToNeutral gamma t

-- TODO: should term at end of block always be of base type? If so, incorporate into syntax?
-- TODO: should things of base type have different case in Term for variables?
genNeutralFrom :: Id -> Type -> NeutralTerm
genNeutralFrom x (ArrowType inputs out)
  = Neutral  x (map (\_ -> HoleTerm []) inputs)
genNeutralFrom x (BaseType bt) = Neutral x []

searchTerm :: Changes -> Term -> Term
searchTerm gamma (LambdaTerm syms bl) = LambdaTerm syms (searchBlock gamma bl)
searchTerm gamma (HoleTerm buffer)
  = HoleTerm (listAcc (map (searchNeutral gamma) buffer))
searchTerm gamma (NeutralTerm t) = case searchNeutral gamma t of
  Left t2 -> NeutralTerm t2
  Right nts -> HoleTerm nts

listAcc :: [Either a [a]] -> [a]
listAcc [] = []
listAcc ((Left a) : es) = a : listAcc es
listAcc ((Right as) : es) = as ++ listAcc es

-- Returns either new term or contents of buffer
searchNeutral :: Changes -> NeutralTerm -> Either NeutralTerm [NeutralTerm]
searchNeutral gamma (Neutral x args) = case lookup x (fst gamma) of
  Nothing -> Left (Neutral x (searchArgs gamma args))
  Just ch -> case ch of
    VariableDeletion -> Right (mapMaybe (termToNeutral gamma) args)
    VariableTypeChange tc -> case tc of
      NoChange -> Left (Neutral x (searchArgs gamma args))
      (TypeReplace ty) -> undefined
        $ genNeutralFrom x ty : mapMaybe (termToNeutral gamma) args
      (ArrowChange ics outc) ->
        let newArgs = map (\case
              Change c n -> chTerm gamma c (args !! n)
              Insert -> HoleTerm []) ics
        in case outc of
          TypeReplace ty -> Left (Neutral x newArgs)
          _ -> Right (mapMaybe (termToNeutral gamma) newArgs)
searchNeutral gamma (MatchTerm x t cases) = case lookup x (snd gamma) of
  Nothing -> Left (MatchTerm x (searchTerm gamma t) (map (searchCase gamma) cases))
  Just dc -> case dc of
    DataTypeDeletion -> Right (mapMaybe (\(Case _ _ b) -> blockToNeutral gamma b) cases)
    (DataTypeChange dcc) -> Left (MatchTerm x (searchTerm gamma t) newCases)
      where newCases :: [Case]
            newCases = map mapper dcc
            mapper :: ConstructorChange -> Case
            -- needs to modify bound vars and add new changes to gamma accordingly.
            mapper (CtrChange ic n) = _w1i
            mapper CtrInsert = Case undefined undefined (Block [] (HoleTerm []))
            -- TODO: CtrInsert should have info about new constsructor.
{-
Something to think about: could just have each datatype definition create an
induction principle in scope (exactly the same as match), which then can use
existing "chTerm", "chArgs", ... to deal with changes.
Advantages:
- No match in syntax
- No "DataChange", merely TypeChange
- No special logic to deal with changing matches
Disadvantages:
- Can't generalize to more general pattern matching
- Can't do stuff like display pattern matches on function inputs.
- Display should still display as match.
  - Perhaps Name = Either String String, and the latter is used for things which
    are displayed as matches?
-}

searchCase :: Changes -> Case -> Case
searchCase = error "not implemented"

-- chNeutral gamma (MatchTerm sym te cas) = _wF gamma

chBlock :: Changes -> TypeChange -> Block -> Block
chBlock gamma c (Block defs t)
  = Block (map (searchDefinition gamma) defs) (chTerm gamma c t)
searchBlock :: Changes -> Block -> Block
searchBlock gamma (Block defs t)
  = Block (map (searchDefinition gamma) defs) (searchTerm gamma  t)

searchDefinition :: Changes -> Definition -> Definition
searchDefinition gamma (TermDefinition x ty t)
  = TermDefinition x (searchType gamma ty) (searchTerm gamma t)
searchDefinition gamma (DataDefinition x ctrs)
  = DataDefinition x (map (searchConstructor gamma) ctrs)

searchConstructor :: Changes -> Constructor -> Constructor
searchConstructor gamma (Constructor x args)
  = Constructor x (map (\(x,t) -> (x, searchType gamma t)) args)

-- TODO: why am I calling it gamma?
-- TODO: no need for "search*" because we can just use NoChange!

{-

-- Convert a term of type T into a term of type (chType T change)
chTerm :: Changes -> TypeChange -> Term -> Term
chTerm = undefined
-- chTerm is what will actually introduce stuff into Changes
-- If input Term is a hole, don't do anything to it (except search with gamma)

searchTerm :: Changes -> Term -> Term
searchTerm gamma (LambdaTerm binds block) = undefined
searchTerm gamma (Neutral x args) = case lookup x (fst gamma) of
  Nothing -> Neutral x (searchArgs gamma args)
  Just ch -> case ch of
    (VariableTypeChange tc) -> case tc of
      (Output tc') -> HoleTerm (newSymbol ()) [undefined {-Neutral x args-}]
      (TypeReplace ty) -> HoleTerm (newSymbol ()) [undefined {-Var x-} {-args...-}] -- put args and var in buffer
      (InputChange ic) -> Neutral x (chArgs args gamma ic)
    VariableDeletion -> HoleTerm (newSymbol ()) [undefined {-args...-}] -- put args in buffer
searchTerm gamma (MatchTerm ty t cases) = case lookup ty (snd gamma) of
  Nothing -> undefined -- use searchCases on cases and also searchTerm on t
  Just dc -> case dc of
    DataTypeDeletion -> HoleTerm (newSymbol ()) []
    (DataTypeChange dc') -> undefined -- call chCases?
searchTerm gamma (HoleTerm h buffer) = undefined -- should gamma also have hole substitutions?

-- TODO: reorder args of functions to make mapping easier
-- TODO: Holes need to have values in them sometimes, e.g. when output is changed
--      Whatever we do with buffers/holes/whatever, this should be handled by the model.
--      This is because stuff in a buffer needs to be updated when an argument is added to a 
--      function or whatever.
-}

{-

Note: lambdas should never be in a buffer.
Instead, if you have "f (lam a . e)", and then
f is deleted, "e[\a]" (e with a turned into holes where it is used)
is placed into the buffer. Everything in a buffer is always a
neutral form, and so buffers DON'T need types on things.

-}