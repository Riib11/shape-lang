module Model where

import Data.Map (Map, lookup)
import Symbol
import Syntax
import Prelude hiding (lookup)

type Permutation = [Int]

-- Change to an argument list
data TypeChange =
    Output TypeChange |
    TypeReplace Type |
    InputChange InputChange

data InputChange = Input Int TypeChange | Insert Int Parameter | Delete Int | Permute Permutation

data DataConstructorChange = ConstructorPermute Permutation
    | DeleteConstructor Int | NewConstructor Int Constructor

-- data Change = VariableTypeChange TypeChange | VariableDeletion | DataTypeDeletion
    -- | DataTypeChange DataChange -- figure out
data VarChange = VariableTypeChange TypeChange | VariableDeletion
data DataChange = DataTypeDeletion | DataTypeChange DataChange

type Changes = (Map Binding VarChange, Map Binding DataChange)

-- Why arent these basic function in haskell's standard library?
deleteAt :: [a] -> Int -> [a]
deleteAt xs i = take i xs ++ drop (i + 1) xs

insertAt :: [a] -> Int -> a -> [a]
insertAt xs i x = take i xs ++ [x] ++ drop i xs

applyAt :: [a] -> Int -> (a -> a) -> [a]
applyAt xs i f = take i xs ++ [f (xs !! i)] ++ drop (i + 1) xs

chType :: Type -> TypeChange -> Type
chType (ArrowType params out) (InputChange (Input i c))
    = ArrowType (applyAt params i (\(name, t) -> (name, chType t c))) out
chType (ArrowType params out) (Output (TypeReplace (BaseType b))) = ArrowType params b -- Should only TypeChange output to a base type!
chType (ArrowType params out) (InputChange (Insert i t)) = ArrowType (insertAt params i t) out
chType (ArrowType params out) (InputChange (Delete i)) = ArrowType (deleteAt params i) out
chType (ArrowType params out) (InputChange (Permute p)) = undefined
chType _ (TypeReplace t) = t
chType _ _ = error "shouldn't get here"

-- convert arguments to a function of type T into arguments to a function of type (chType T change)
chArgs :: [Term] -> Changes -> InputChange -> [Term]
chArgs args gamma (Insert i p) =
  insertAt (searchArgs gamma args) i (HoleTerm (newSymbol ()) undefined undefined)
chArgs args gamma (Input i c) = searchArgs gamma (applyAt args i (\t -> chTerm t gamma c))
chArgs args gamma (Delete i) = searchArgs gamma (deleteAt args i)
chArgs args gamma (Permute p) = undefined

searchArgs :: Changes -> [Term] -> [Term]
searchArgs gamma = map (searchTerm gamma)

-- Convert a term of type T into a term of type (chType T change)
chTerm :: Term -> Changes -> TypeChange -> Term
chTerm = undefined
-- chTerm is what will actually introduce stuff into Changes

searchTerm :: Changes -> Term -> Term
searchTerm gamma (LambdaTerm binds block) = undefined
searchTerm gamma (NeutralTerm x args) = case lookup x (fst gamma) of
  Nothing -> NeutralTerm x (searchArgs gamma args)
  Just ch -> case ch of
    (VariableTypeChange tc) -> case tc of
      (Output tc') -> HoleTerm (newSymbol ()) undefined undefined -- Really, old args should go in hole?
      (TypeReplace ty) -> HoleTerm (newSymbol ()) undefined undefined -- Really, old args should go in hole?
      (InputChange ic) -> NeutralTerm x (chArgs args gamma ic)
    VariableDeletion -> HoleTerm (newSymbol ()) undefined undefined
searchTerm gamma (MatchTerm ty t cases) = case lookup ty (snd gamma) of
  Nothing -> undefined -- use searchCases on cases and also searchTerm on t
  Just dc -> case dc of
    DataTypeDeletion -> HoleTerm (newSymbol ()) undefined undefined
    (DataTypeChange dc') -> undefined -- call chCases?
searchTerm gamma (HoleTerm h _ _) = undefined -- should gamma also have hole substitutions?

-- TODO: reorder args of functions to make mapping easier
-- TODO: Holes need to have values in them sometimes, e.g. when output is changed
--      Whatever we do with buffers/holes/whatever, this should be handled by the model.
--      This is because stuff in a buffer needs to be updated when an argument is added to a 
--      function or whatever.

{-

Problem: suppose that we have a program like

Data A
let g : A -> B
let f : B
    f = g a

Then the user deltes the type A.

The algorithm will discover that g has a VarChange which is (Input 0 (TypeReplace (Hole ...)))
So everywhere that g is called, this change will be in gamma, and it will cause the first arg
of g to be dug.
BUT then this needs to be applied inside the body of f.
Even worse, g and f could have been defined in the opposite order, so g could be above f.

searchBlock will have to be designed to deal with this case. It will need to first find all
of the changes on each declaration, and only afterwards call searchTerm on the body of each
declaration with those changes in gamma.

-}