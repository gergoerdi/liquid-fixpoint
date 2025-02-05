{-# LANGUAGE CPP                       #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE UndecidableInstances      #-}
{-# LANGUAGE PatternGuards             #-}
{-# LANGUAGE ViewPatterns              #-}

{-# OPTIONS_GHC -Wno-orphans           #-}

module Language.Fixpoint.Smt.Theories
     (
       -- * Convert theory applications TODO: merge with smt2symbol
       smt2App
       -- * Convert theory sorts
     , sortSmtSort

       -- * Convert theory symbols
     , smt2Symbol

       -- * Preamble to initialize SMT
     , preamble

       -- * Bit Vector Operations
     , sizeBv
       -- , toInt

       -- * Theory Symbols
     , theorySymbols
     , dataDeclSymbols

       -- * Theories
     , setEmpty, setEmp, setSng, setAdd, setMem
     , setCom, setCap, setCup, setDif, setSub

     , mapDef, mapSel, mapSto

     , bagEmpty, bagSng, bagCount, bagSub, bagCup, bagMax, bagMin

     -- * Z3 theory array encodings

     , arrConstM, arrStoreM, arrSelectM

     , arrConstS, arrStoreS, arrSelectS
     , arrMapNotS, arrMapOrS, arrMapAndS, arrMapImpS

     , arrConstB, arrStoreB, arrSelectB
     , arrMapPlusB, arrMapLeB, arrMapGtB, arrMapIteB

      -- * Query Theories
     , isSmt2App
     , axiomLiterals
     , maxLamArg
     ) where

import           Prelude hiding (map)
import           Data.ByteString.Builder (Builder)
import           Language.Fixpoint.Types.Sorts
import           Language.Fixpoint.Types.Config
import           Language.Fixpoint.Types
import           Language.Fixpoint.Smt.Types
-- import qualified Data.HashMap.Strict      as M
import           Data.Maybe (catMaybes)
-- import           Data.Text.Format
import qualified Data.Text
import           Data.String                 (IsString(..))
import Language.Fixpoint.Utils.Builder

{- | [NOTE:Adding-Theories] To add new (SMTLIB supported) theories to
     liquid-fixpoint and upstream, grep for "Map_default" and then add
     your corresponding symbol in all those places.
     This is currently far more complicated than it needs to be.
 -}

--------------------------------------------------------------------------------
-- | Theory Symbols ------------------------------------------------------------
--------------------------------------------------------------------------------

---- Size changes
bvConcatName, bvExtractName, bvRepeatName, bvZeroExtName, bvSignExtName :: Symbol
bvConcatName   = "concat"
bvExtractName  = "extract"
bvRepeatName   = "repeat"
bvZeroExtName  = "zero_extend"
bvSignExtName  = "sign_extend"

-- Unary Logic
bvNotName, bvNegName :: Symbol
bvNotName = "bvnot"
bvNegName = "bvneg"

-- Binary Logic
bvAndName, bvNandName, bvOrName, bvNorName, bvXorName, bvXnorName :: Symbol
bvAndName  = "bvand"
bvNandName = "bvnand"
bvOrName   = "bvor"
bvNorName  = "bvnor"
bvXorName  = "bvxor"
bvXnorName = "bvxnor"

-- Shifts
bvShlName, bvLShrName, bvAShrName, bvLRotName, bvRRotName :: Symbol
bvShlName  = "bvshl"
bvLShrName = "bvlshr"
bvAShrName = "bvashr"
bvLRotName = "rotate_left"
bvRRotName = "rotate_right"

-- Arithmetic
bvAddName, bvSubName, bvMulName, bvUDivName :: Symbol
bvURemName, bvSDivName, bvSRemName, bvSModName :: Symbol
bvAddName  = "bvadd"
bvSubName  = "bvsub"
bvMulName  = "bvmul"
bvUDivName = "bvudiv"
bvURemName = "bvurem"
bvSDivName = "bvsdiv"
bvSRemName = "bvsrem"
bvSModName = "bvsmod"

-- Comparisons
bvCompName, bvULtName, bvULeName, bvUGtName, bvUGeName :: Symbol
bvSLtName, bvSLeName, bvSGtName, bvSGeName :: Symbol
bvCompName = "bvcomp"
bvULtName  = "bvult"
bvULeName  = "bvule"
bvUGtName  = "bvugt"
bvUGeName  = "bvuge"
bvSLtName  = "bvslt"
bvSLeName  = "bvsle"
bvSGtName  = "bvsgt"
bvSGeName  = "bvsge"

setEmpty, setEmp, setCap, setSub, setAdd, setMem, setCom, setCup, setDif, setSng :: (IsString a) => a -- Symbol
setEmpty = "Set_empty"
setEmp   = "Set_emp"
setCap   = "Set_cap"
setSub   = "Set_sub"
setAdd   = "Set_add"
setMem   = "Set_mem"
setCom   = "Set_com"
setCup   = "Set_cup"
setDif   = "Set_dif"
setSng   = "Set_sng"

mapDef, mapSel, mapSto :: (IsString a) => a
mapDef   = "Map_default"
mapSel   = "Map_select"
mapSto   = "Map_store"

bagEmpty, bagSng, bagCount, bagSub, bagCup, bagMax, bagMin :: (IsString a) => a
bagEmpty = "Bag_empty"
bagSng   = "Bag_sng"
bagCount = "Bag_count"
bagSub   = "Bag_sub"
bagCup   = "Bag_union"
bagMax   = "Bag_union_max" -- See [Bag max and min]
bagMin   = "Bag_inter_min"

-- [Bag max and min]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Functions bagMax and bagMin: Union/intersect two bags, combining the elements by
-- taking either the greatest (bagMax) or the least (bagMin) of them.
--   bagMax, bagMin : Map v Int -> Map v Int -> Map v Int

--- Array operations for sets
arrConstS, arrStoreS, arrSelectS, arrMapNotS, arrMapOrS, arrMapAndS, arrMapImpS :: Symbol
arrConstS  = "arr_const_s"
arrStoreS  = "arr_store_s"
arrSelectS = "arr_select_s"

arrMapNotS = "arr_map_not"
arrMapOrS  = "arr_map_or"
arrMapAndS = "arr_map_and"
arrMapImpS = "arr_map_imp"

--- Array operations for polymorphic maps
arrConstM, arrStoreM, arrSelectM :: Symbol
arrConstM  = "arr_const_m"
arrStoreM  = "arr_store_m"
arrSelectM = "arr_select_m"

--- Array operations for bags
arrConstB, arrStoreB, arrSelectB :: Symbol
arrConstB  = "arr_const_b"
arrStoreB  = "arr_store_b"
arrSelectB = "arr_select_b"

arrMapPlusB, arrMapLeB, arrMapGtB, arrMapIteB :: Symbol
arrMapPlusB = "arr_map_plus"
arrMapLeB   = "arr_map_le"
arrMapGtB   = "arr_map_gt"
arrMapIteB   = "arr_map_ite"

strLen, strSubstr, strConcat :: (IsString a) => a -- Symbol
strLen    = "strLen"
strSubstr = "subString"
strConcat = "concatString"

z3strlen, z3strsubstr, z3strconcat :: Raw
z3strlen    = "str.len"
z3strsubstr = "str.substr"
z3strconcat = "str.++"

strLenSort, substrSort, concatstrSort :: Sort
strLenSort    = FFunc strSort intSort
substrSort    = mkFFunc 0 [strSort, intSort, intSort, strSort]
concatstrSort = mkFFunc 0 [strSort, strSort, strSort]

string :: Raw
string = strConName

bFun :: Raw -> [(Builder, Builder)] -> Builder -> Builder -> Builder
bFun name xts out body = key "define-fun" (seqs [fromText name, args, out, body])
  where
    args = parenSeqs [parens (x <+> t) | (x, t) <- xts]

bFun' :: Raw -> [Builder] -> Builder -> Builder
bFun' name ts out = key "declare-fun" (seqs [fromText name, args, out])
  where
    args = parenSeqs ts

bSort :: Raw -> Builder -> Builder
bSort name def = key "define-sort" (fromText name <+> "()" <+> def)

z3Preamble :: Config -> [Builder]
z3Preamble u
  = stringPreamble u ++
    [ bFun boolToIntName
        [("b", "Bool")]
        "Int"
        "(ite b 1 0)"

    , uifDef u (symbolText mulFuncName) "*"
    , uifDef u (symbolText divFuncName) "div"
    ]

-- RJ: Am changing this to `Int` not `Real` as (1) we usually want `Int` and
-- (2) have very different semantics. TODO: proper overloading, post genEApp
uifDef :: Config -> Data.Text.Text -> Data.Text.Text -> Builder
uifDef cfg f op
  | linear cfg || Z3 /= solver cfg
  = bFun' f ["Int", "Int"] "Int"
  | otherwise
  = bFun f [("x", "Int"), ("y", "Int")] "Int" (key2 (fromText op) "x" "y")

cvc4Preamble :: Config -> [Builder]
cvc4Preamble z
  = "(set-logic ALL_SUPPORTED)" : commonPreamble z

commonPreamble :: Config -> [Builder]
commonPreamble _ --TODO use uif flag u (see z3Preamble)
  = [ bSort string "Int"
    , bFun boolToIntName [("b", "Bool")] "Int" "(ite b 1 0)"
    ]

stringPreamble :: Config -> [Builder]
stringPreamble cfg | stringTheory cfg
  = [ bSort string "String"
    , bFun strLen [("s", fromText string)] "Int" (key (fromText z3strlen) "s")
    , bFun strSubstr [("s", fromText string), ("i", "Int"), ("j", "Int")] (fromText string) (key (fromText z3strsubstr) "s i j")
    , bFun strConcat [("x", fromText string), ("y", fromText string)] (fromText string) (key (fromText z3strconcat) "x y")
    ]

stringPreamble _
  = [ bSort string "Int"
    , bFun' strLen [fromText string] "Int"
    , bFun' strSubstr [fromText string, "Int", "Int"] (fromText string)
    , bFun' strConcat [fromText string, fromText string] (fromText string)
    ]

--------------------------------------------------------------------------------
-- | Exported API --------------------------------------------------------------
--------------------------------------------------------------------------------
smt2Symbol :: SymEnv -> Symbol -> Maybe Builder
smt2Symbol env x = fromText . tsRaw <$> symEnvTheory x env

instance SMTLIB2 SmtSort where
  smt2 _ = smt2SmtSort

smt2SmtSort :: SmtSort -> Builder
smt2SmtSort SInt         = "Int"
smt2SmtSort SReal        = "Real"
smt2SmtSort SBool        = "Bool"
smt2SmtSort SString      = fromText string
--smt2SmtSort SSet         = fromText set
--smt2SmtSort SMap         = fromText map
smt2SmtSort (SArray a b) = key2 "Array" (smt2SmtSort a) (smt2SmtSort b)
smt2SmtSort (SBitVec n)  = key "_ BitVec" (bShow n)
smt2SmtSort (SVar n)     = "T" <> bShow n
smt2SmtSort (SData c []) = symbolBuilder c
smt2SmtSort (SData c ts) = parenSeqs [symbolBuilder c, smt2SmtSorts ts]

-- smt2SmtSort (SApp ts)    = build "({} {})" (symbolBuilder tyAppName, smt2SmtSorts ts)

smt2SmtSorts :: [SmtSort] -> Builder
smt2SmtSorts = seqs . fmap smt2SmtSort

type VarAs = SymEnv -> Symbol -> Sort -> Builder
--------------------------------------------------------------------------------
smt2App :: VarAs -> SymEnv -> Expr -> [Builder] -> Maybe Builder
--------------------------------------------------------------------------------
smt2App _ env ex@(dropECst -> EVar f) [d]
  | f == arrConstS = Just (key (key "as const" (getTarget ex)) d)
  | f == arrConstB = Just (key (key "as const" (getTarget ex)) d)
  | f == arrConstM = Just (key (key "as const" (getTarget ex)) d)
  where
    getTarget :: Expr -> Builder
    -- const is a function, but SMT expects only the output sort
    getTarget (ECst _ t) = smt2SmtSort $ sortSmtSort True (seData env) (ffuncOut t)
    getTarget e = bShow e

smt2App k env ex (builder:builders)
  | Just fb <- smt2AppArg k env ex
  = Just $ key fb (builder <> mconcat [ " " <> d | d <- builders])

smt2App _ _ _ _    = Nothing

smt2AppArg :: VarAs -> SymEnv -> Expr -> Maybe Builder
smt2AppArg k env (ECst (dropECst -> EVar f) t)
  | Just fThy <- symEnvTheory f env
  = Just $ if isPolyCtor fThy t
            then k env f (ffuncOut t)
            else fromText (tsRaw fThy)

smt2AppArg _ _ _
  = Nothing

isPolyCtor :: TheorySymbol -> Sort -> Bool
isPolyCtor fThy t = isPolyInst (tsSort fThy) t && tsInterp fThy == Ctor

ffuncOut :: Sort -> Sort
ffuncOut t = maybe t (last . snd) (bkFFunc t)

--------------------------------------------------------------------------------
isSmt2App :: SEnv TheorySymbol -> Expr -> Maybe Int
--------------------------------------------------------------------------------
isSmt2App g (dropECst -> EVar f) = lookupSEnv f g >>= thyAppInfo
isSmt2App _  _                   = Nothing

thyAppInfo :: TheorySymbol -> Maybe Int
thyAppInfo ti = case tsInterp ti of
  Field    -> Just 1
  _        -> sortAppInfo (tsSort ti)

sortAppInfo :: Sort -> Maybe Int
sortAppInfo t = case bkFFunc t of
  Just (_, ts) -> Just (length ts - 1)
  Nothing      -> Nothing

preamble :: Config -> SMTSolver -> [Builder]
preamble u Z3   = z3Preamble u
preamble u Cvc4 = cvc4Preamble u
preamble u _    = commonPreamble u

--------------------------------------------------------------------------------
-- | Theory Symbols : `uninterpSEnv` should be disjoint from see `interpSEnv`
--   to avoid duplicate SMT definitions.  `uninterpSEnv` is for uninterpreted
--   symbols, and `interpSEnv` is for interpreted symbols.
--------------------------------------------------------------------------------

-- | `theorySymbols` contains the list of ALL SMT symbols with interpretations,
--   i.e. which are given via `define-fun` (as opposed to `declare-fun`)
theorySymbols :: [DataDecl] -> SEnv TheorySymbol -- M.HashMap Symbol TheorySymbol
theorySymbols ds = fromListSEnv $  -- SHIFTLAM uninterpSymbols
                                  interpSymbols
                               ++ concatMap dataDeclSymbols ds


--------------------------------------------------------------------------------
interpSymbols :: [(Symbol, TheorySymbol)]
--------------------------------------------------------------------------------
interpSymbols =
  [
  -- TODO we'll probably need two versions of these - one for sets and one for maps
    interpSym arrConstS  "const"  (FAbs 0 $ FFunc boolSort setArrSort)
  , interpSym arrSelectS "select" (FAbs 0 $ FFunc setArrSort $ FFunc (FVar 0) boolSort)
  , interpSym arrStoreS  "store"  (FAbs 0 $ FFunc setArrSort $ FFunc (FVar 0) $ FFunc boolSort setArrSort)

  , interpSym arrMapNotS "(_ map not)" (FFunc setArrSort setArrSort)
  , interpSym arrMapOrS  "(_ map or)"  (FFunc setArrSort $ FFunc setArrSort setArrSort)
  , interpSym arrMapAndS "(_ map and)" (FFunc setArrSort $ FFunc setArrSort setArrSort)
  , interpSym arrMapImpS "(_ map =>)"  (FFunc setArrSort $ FFunc setArrSort setArrSort)

  , interpSym arrConstM  "const"  (FAbs 0 $ FFunc (FVar 1) mapArrSort)
  , interpSym arrSelectM "select" (FAbs 0 $ FFunc mapArrSort $ FFunc (FVar 0) (FVar 1))
  , interpSym arrStoreM  "store"  (FAbs 0 $ FFunc mapArrSort $ FFunc (FVar 0) $ FFunc (FVar 1) mapArrSort)

  , interpSym arrConstB  "const"  (FAbs 0 $ FFunc intSort bagArrSort)
  , interpSym arrSelectB "select" (FAbs 0 $ FFunc bagArrSort $ FFunc (FVar 0) intSort)
  , interpSym arrStoreB  "store"  (FAbs 0 $ FFunc bagArrSort $ FFunc (FVar 0) $ FFunc intSort bagArrSort)

  , interpSym arrMapPlusB "(_ map (+ (Int Int) Int))"        (FFunc bagArrSort $ FFunc bagArrSort bagArrSort)
  , interpSym arrMapLeB   "(_ map (<= (Int Int) Bool))"      (FFunc bagArrSort $ FFunc bagArrSort setArrSort)
  , interpSym arrMapGtB   "(_ map (> (Int Int) Bool))"       (FFunc bagArrSort $ FFunc bagArrSort setArrSort)
  , interpSym arrMapIteB  "(_ map (ite (Bool Int Int) Int))" (FFunc setArrSort $ FFunc bagArrSort $ FFunc bagArrSort bagArrSort)

  , interpSym setEmp   setEmp   (FAbs 0 $ FFunc (setSort $ FVar 0) boolSort)
  , interpSym setEmpty setEmpty (FAbs 0 $ FFunc intSort (setSort $ FVar 0))
  , interpSym setSng   setSng   (FAbs 0 $ FFunc (FVar 0) (setSort $ FVar 0))
  , interpSym setAdd   setAdd   setAddSort
  , interpSym setCup   setCup   setBopSort
  , interpSym setCap   setCap   setBopSort
  , interpSym setMem   setMem   setMemSort
  , interpSym setDif   setDif   setBopSort
  , interpSym setSub   setSub   setCmpSort
  , interpSym setCom   setCom   setCmpSort

  , interpSym mapDef   mapDef  mapDefSort
  , interpSym mapSel   mapSel  mapSelSort
  , interpSym mapSto   mapSto  mapStoSort

  , interpSym bagEmpty bagEmpty (FAbs 0 $ FFunc intSort (bagSort $ FVar 0))
  , interpSym bagSng   bagSng   (FAbs 0 $ FFunc (FVar 0) $ FFunc intSort (setSort $ FVar 0))
  , interpSym bagCount bagCount bagCountSort
  , interpSym bagCup   bagCup   bagBopSort
  , interpSym bagMax   bagMax   bagBopSort
  , interpSym bagMin   bagMin   bagBopSort
  , interpSym bagSub   bagSub   bagSubSort

  -- , interpSym bvOrName  "bvor"  bvBopSort
  -- , interpSym bvAndName "bvand" bvBopSort
  -- , interpSym bvAddName "bvadd" bvBopSort
  -- , interpSym bvSubName "bvsub" bvBopSort

  , interpSym strLen    strLen    strLenSort
  , interpSym strSubstr strSubstr substrSort
  , interpSym strConcat strConcat concatstrSort
  , interpSym boolInt   boolInt   (FFunc boolSort intSort)

  -- Function mappings for indexed identifier functions
  , interpSym' "_" iiSort
  , interpSym "app" "" appSort

  , interpSym' bvConcatName bvConcatSort
  , interpSym' bvExtractName (FFunc FInt bvExtendSort)
  , interpBvExt bvRepeatName
  , interpBvExt bvZeroExtName
  , interpBvExt bvSignExtName

  , interpBvUop bvNotName
  , interpBvUop bvNegName

  , interpBvBop bvAndName
  , interpBvBop bvNandName
  , interpBvBop bvOrName
  , interpBvBop bvNorName
  , interpBvBop bvXorName
  , interpBvBop bvXnorName

  , interpBvBop bvShlName
  , interpBvBop bvLShrName
  , interpBvBop bvAShrName
  , interpBvRot bvLRotName
  , interpBvRot bvRRotName

  , interpBvBop bvAddName
  , interpBvBop bvSubName
  , interpBvBop bvMulName
  , interpBvBop bvUDivName
  , interpBvBop bvURemName
  , interpBvBop bvSDivName
  , interpBvBop bvSRemName
  , interpBvBop bvSModName

  , interpSym' bvCompName bvEqSort
  , interpBvCmp bvULtName
  , interpBvCmp bvULeName
  , interpBvCmp bvUGtName
  , interpBvCmp bvUGeName
  , interpBvCmp bvSLtName
  , interpBvCmp bvSLeName
  , interpBvCmp bvSGtName
  , interpBvCmp bvSGeName

  , interpSym intbv32Name "(_ int2bv 32)"   (FFunc intSort bv32)
  , interpSym intbv64Name "(_ int2bv 64)"   (FFunc intSort bv64)
  , interpSym bv32intName  "(_ bv2int 32)"  (FFunc bv32    intSort)
  , interpSym bv64intName   "(_ bv2int 64)" (FFunc bv64    intSort)

  ]
  where
    mapArrSort = arraySort (FVar 0) (FVar 1)
    setArrSort = arraySort (FVar 0) boolSort
    bagArrSort = arraySort (FVar 0) intSort
    -- (sizedBitVecSort "Size1")
    bv32       = sizedBitVecSort "Size32"
    bv64       = sizedBitVecSort "Size64"
    boolInt    = boolToIntName

    setAddSort = FAbs 0 $ FFunc (setSort $ FVar 0) $ FFunc (FVar 0)           (setSort $ FVar 0)
    setBopSort = FAbs 0 $ FFunc (setSort $ FVar 0) $ FFunc (setSort $ FVar 0) (setSort $ FVar 0)
    setMemSort = FAbs 0 $ FFunc (FVar 0) $ FFunc (setSort $ FVar 0) boolSort
    setCmpSort = FAbs 0 $ FFunc (setSort $ FVar 0) $ FFunc (setSort $ FVar 0) boolSort

    mapDefSort = FAbs 0 $ FAbs 1 $ FFunc (FVar 1)
                                         (mapSort (FVar 0) (FVar 1))
    -- select :: forall k v. Map k v -> k -> v
    mapSelSort = FAbs 0 $ FAbs 1 $ FFunc (mapSort (FVar 0) (FVar 1))
                                 $ FFunc (FVar 0) (FVar 1)
    -- store :: forall k v. Map k v -> k -> v -> Map k v
    mapStoSort = FAbs 0 $ FAbs 1 $ FFunc (mapSort (FVar 0) (FVar 1))
                                 $ FFunc (FVar 0)
                                 $ FFunc (FVar 1)
                                         (mapSort (FVar 0) (FVar 1))

    bagCountSort = FAbs 0 $ FFunc (FVar 0) $ FFunc (bagSort $ FVar 0) intSort
    -- cup :: forall i. Map i Int -> Map i Int -> Map i Int
    bagBopSort = FAbs 0          $ FFunc (bagSort $ FVar 0)
                                 $ FFunc (bagSort $ FVar 0)
                                         (bagSort $ FVar 0)
    bagSubSort = FAbs 0 $ FFunc (bagSort $ FVar 0) $ FFunc (bagSort $ FVar 0) boolSort
interpBvUop :: Symbol -> (Symbol, TheorySymbol)
interpBvUop name = interpSym' name bvUopSort
interpBvBop :: Symbol -> (Symbol, TheorySymbol)
interpBvBop name = interpSym' name bvBopSort
interpBvCmp :: Symbol -> (Symbol, TheorySymbol)
interpBvCmp name = interpSym' name bvCmpSort
interpBvExt :: Symbol -> (Symbol, TheorySymbol)
interpBvExt name = interpSym' name bvExtendSort
interpBvRot :: Symbol -> (Symbol, TheorySymbol)
interpBvRot name = interpSym' name bvRotSort

interpSym' :: Symbol -> Sort -> (Symbol, TheorySymbol)
interpSym' name = interpSym name (Data.Text.pack $ symbolString name)

-- Indexed Identifier sort.
-- Together with 'app', this allows one to write indexed identifier
-- functions (smtlib2 specific functions). (e.g. ((_ sign_extend 1) bv))
--
-- The idea here is that 'app' is elaborated to the empty string,
-- and '_' does the typelit application as it does in smtlib2.
--
-- Then if we write, (app (_ sign_extend 1) bv), LF will elaborate
-- it as ( (_ sign_extend 1) bv). Fitting the smtlib2 format exactly!
--
-- One thing to note, is that any indexed identifier function (like
-- sign_extend) has to have no FAbs in it. Otherwise, they will be
-- elaborated like e.g. ( (_ (as sign_extend Int) 1) bv), which is wrong!
--
-- _ :: forall a b c. (a -> b -> c) -> a -> (b -> c)
iiSort :: Sort
iiSort = FAbs 0 $ FAbs 1 $ FAbs 2 $ FFunc
               (FFunc (FVar 0) $ FFunc (FVar 1) (FVar 2))
               (FFunc (FVar 0) $ FFunc (FVar 1) (FVar 2))

-- Simple application, used for indexed identifier function, check '_'.
--
-- app :: forall a b. (a -> b) -> a -> b
appSort :: Sort
appSort = FAbs 0 $ FAbs 1 $ FFunc
                (FFunc (FVar 0) (FVar 1))
                (FFunc (FVar 0) (FVar 1))

-- Indexed identifier operation, purposely didn't place FAbs!
--
-- extend :: Int -> BitVec a -> BitVec b
bvExtendSort :: Sort
bvExtendSort  = FFunc FInt $ FFunc (bitVecSort 1) (bitVecSort 2)

-- Indexed identifier operation, purposely didn't place FAbs!
--
-- rot :: Int -> BitVec a -> BitVec a
bvRotSort :: Sort
bvRotSort  = FFunc FInt $ FFunc (bitVecSort 0) (bitVecSort 0)

-- uOp :: forall a. BitVec a -> BitVec a
bvUopSort :: Sort
bvUopSort = FAbs 0 $ FFunc (bitVecSort 0) (bitVecSort 0)

-- bOp :: forall a. BitVec a -> BitVec a -> BitVec a
bvBopSort :: Sort
bvBopSort = FAbs 0 $ FFunc (bitVecSort 0) $ FFunc (bitVecSort 0) (bitVecSort 0)
-- bvBopSort = FAbs 0 $ FFunc (bitVecSort (FVar 0)) (FFunc (bitVecSort (FVar 0)) (bitVecSort (FVar 0)))

-- cmp :: forall a. BitVec a -> BitVec a -> Bool
bvCmpSort :: Sort
bvCmpSort = FAbs 0 $ FFunc (bitVecSort 0) $ FFunc (bitVecSort 0) boolSort

-- eq :: forall a. BitVec a -> BitVec a -> BitVec 1
bvEqSort :: Sort
bvEqSort = FAbs 0 $ FFunc (bitVecSort 0) $ FFunc (bitVecSort 0) (sizedBitVecSort "Size1")

-- concat :: forall a b c. BitVec a -> BitVec b -> BitVec c
bvConcatSort :: Sort
bvConcatSort = FAbs 0 $ FAbs 1 $ FAbs 2 $
                     FFunc (bitVecSort 0) $ FFunc (bitVecSort 1) (bitVecSort 2)

interpSym :: Symbol -> Raw -> Sort -> (Symbol, TheorySymbol)
interpSym x n t = (x, Thy x n t Theory)

maxLamArg :: Int
maxLamArg = 7

axiomLiterals :: [(Symbol, Sort)] -> [Expr]
axiomLiterals lts = catMaybes [ lenAxiom l <$> litLen l | (l, t) <- lts, isString t ]
  where
    lenAxiom l n  = EEq (EApp (expr (strLen :: Symbol)) (expr l)) (expr n `ECst` intSort)
    litLen        = fmap (Data.Text.length .  symbolText) . unLitSymbol

--------------------------------------------------------------------------------
-- | Constructors, Selectors and Tests from 'DataDecl'arations.
--------------------------------------------------------------------------------
dataDeclSymbols :: DataDecl -> [(Symbol, TheorySymbol)]
dataDeclSymbols d = ctorSymbols d ++ testSymbols d ++ selectSymbols d

-- | 'selfSort d' returns the _self-sort_ of 'd' :: 'DataDecl'.
--   See [NOTE:DataDecl] for details.

selfSort :: DataDecl -> Sort
selfSort (DDecl c n _) = fAppTC c (FVar <$> [0..(n-1)])

-- | 'fldSort d t' returns the _real-sort_ of 'd' if 't' is the _self-sort_
--   and otherwise returns 't'. See [NOTE:DataDecl] for details.

fldSort :: DataDecl -> Sort -> Sort
fldSort d (FTC c)
  | c == ddTyCon d = selfSort d
fldSort _ s        = s

--------------------------------------------------------------------------------
ctorSymbols :: DataDecl -> [(Symbol, TheorySymbol)]
--------------------------------------------------------------------------------
ctorSymbols d = ctorSort d <$> ddCtors d

ctorSort :: DataDecl -> DataCtor -> (Symbol, TheorySymbol)
ctorSort d ctor = (x, Thy x (symbolRaw x) t Ctor)
  where
    x           = symbol ctor
    t           = mkFFunc n (ts ++ [selfSort d])
    n           = ddVars d
    ts          = fldSort d . dfSort <$> dcFields ctor

--------------------------------------------------------------------------------
testSymbols :: DataDecl -> [(Symbol, TheorySymbol)]
--------------------------------------------------------------------------------
testSymbols d = testTheory t . symbol <$> ddCtors d
  where
    t         = mkFFunc (ddVars d) [selfSort d, boolSort]

testTheory :: Sort -> Symbol -> (Symbol, TheorySymbol)
testTheory t x = (sx, Thy sx raw t Test)
  where
    sx         = testSymbol x
    raw        = "is-" <> symbolRaw x

symbolRaw :: Symbol -> Data.Text.Text
symbolRaw = symbolSafeText

--------------------------------------------------------------------------------
selectSymbols :: DataDecl -> [(Symbol, TheorySymbol)]
--------------------------------------------------------------------------------
selectSymbols d = theorify <$> concatMap (ctorSelectors d) (ddCtors d)

-- | 'theorify' converts the 'Sort' into a full 'TheorySymbol'
theorify :: (Symbol, Sort) -> (Symbol, TheorySymbol)
theorify (x, t) = (x, Thy x (symbolRaw x) t Field)

ctorSelectors :: DataDecl -> DataCtor -> [(Symbol, Sort)]
ctorSelectors d ctor = fieldSelector d <$> dcFields ctor

fieldSelector :: DataDecl -> DataField -> (Symbol, Sort)
fieldSelector d f = (symbol f, mkFFunc n [selfSort d, ft])
  where
    ft            = fldSort d $ dfSort f
    n             = ddVars  d

{- | [NOTE:DataDecl]  This note explains the set of symbols generated
     for the below data-declaration:

  data Vec 1 = [
    | nil  { }
    | cons { vHead : @(0), vTail : Vec}
  ]

We call 'Vec' the _self-sort_ of the data-type, and we want to ensure that
in all constructors, tests and selectors, the _self-sort_ is replaced with
the actual sort, namely, 'Vec @(0)'.

Constructors  // ctor : (fld-sorts) => me

        nil   : func(1, [Vec @(0)])
        cons  : func(1, [@(0); Vec @(0); Vec @(0)])

Tests         // is#ctor : (me) => bool

      is#nil  : func(1, [Vec @(0); bool])
      is#cons : func(1, [Vec @(0); bool])

Selectors     // fld : (me) => fld-sort

      vHead   : func(1, [Vec @(0); @(0)])
      vTail   : func(1, [Vec @(0); Vec @(0)])

-}
