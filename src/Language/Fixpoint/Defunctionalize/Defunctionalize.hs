{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE TupleSections        #-}
{-# LANGUAGE PatternGuards        #-}
{-# LANGUAGE OverloadedStrings    #-}

-- | Defunctionalization of higher order logic

module Language.Fixpoint.Defunctionalize.Defunctionalize (defunctionalize) where

import           Language.Fixpoint.Misc            (secondM, errorstar, mapSnd)
import           Language.Fixpoint.Solver.Validate (symbolSorts)
import           Language.Fixpoint.Types        hiding (allowHO)
import           Language.Fixpoint.Types.Config -- hiding (eliminate)
import           Language.Fixpoint.SortCheck
import           Language.Fixpoint.Types.Visitor   (stripCasts, mapExpr, mapMExpr)

import qualified Language.Fixpoint.Smt.Theories as Thy
import           Control.Monad.State
import qualified Data.HashMap.Strict as M
import           Data.Hashable
import qualified Data.List           as L

import qualified Data.Text                 as T

defunctionalize :: (Fixpoint a) => Config -> SInfo a -> SInfo a
defunctionalize cfg si = evalState (defunc si) (makeInitDFState cfg si)

class Defunc a where
  defunc :: a -> DF a

--------------------------------------------------------------------------------
-- | Sort defunctionalization [should be done by elaboration] ------------------
--------------------------------------------------------------------------------
-- NOPROP instance Defunc Sort where
-- NOPROP   defunc = return . defuncSort
-- NOPROP defuncSort :: Sort -> DF Sort
-- NOPROP defuncSort s = do
  -- NOPROP hoFlag <- dfHO <$> get
  -- NOPROP return $ if hoFlag then go s else s

--------------------------------------------------------------------------------
-- | Expressions defunctionalization -------------------------------------------
--------------------------------------------------------------------------------
instance Defunc Expr where
  defunc = txExpr

txCastedExpr :: Expr -> DF Expr
txCastedExpr = txExpr

txExpr :: Expr -> DF Expr
txExpr e = do
  -- NOPROP env    <- dfenv <$> get
  hoFlag <- dfHO  <$> get
  exFlag <- dfExt <$> get
  stFlag <- dfStr <$> get
  txExpr' stFlag hoFlag exFlag e -- [NOTE: NOPROP all `Expr` should be elaborated prior to defunc]

txExpr' :: Bool -> Bool -> Bool -> Expr -> DF Expr
txExpr' stFlag hoFlag exFlag e
  | exFlag && hoFlag
  = (txExtensionality . txnumOverloading <$> txStr stFlag e) >>= defuncExpr
  | hoFlag
  = (txnumOverloading <$> txStr stFlag e) >>= defuncExpr
  | otherwise
  = txnumOverloading <$> txStr stFlag e


defuncExpr :: Expr -> DF Expr
defuncExpr = {- writeLog ("DEFUNC EXPR " ++ showpp (eliminate e)) >> -} go Nothing
  where
    go _ e@(ESym _)       = return e
    go _ e@(ECon _)       = return e
    go _ e@(EVar _)       = return e
    go _ e@(PKVar _ _)    = return e
    go s e@(EApp e1 e2)   = logRedex e >> (EApp <$> go s e1 <*> go s e2)    -- NOPROP : defuncEApp moved to elaborate
    go s (ENeg e)         = ENeg <$> go s e
    go _ (EBin o e1 e2)   = EBin o <$> go Nothing e1 <*> go Nothing e2
    go s (EIte e1 e2 e3)  = EIte <$> go (Just boolSort) e1 <*> go s e2 <*> go s e3
    go _ (ECst e t)       = (`ECst` t) <$> go (Just t) e
    go _ (PTrue)          = return PTrue
    go _ (PFalse)         = return PFalse
    go _ (PAnd [])        = return PTrue
    go _ (PAnd ps)        = PAnd <$> mapM (go (Just boolSort)) ps
    go _ (POr [])         = return PFalse
    go _ (POr ps)         = POr <$> mapM (go (Just boolSort)) ps
    go _ (PNot p)         = PNot <$> go (Just boolSort) p
    go _ (PImp p q)       = PImp <$> go (Just boolSort) p <*> go (Just boolSort) q
    go _ (PIff p q)       = PIff <$> go (Just boolSort) p <*> go (Just boolSort) q
    go _ (PExist bs p)    = PExist bs <$> withExtendedEnv bs (go (Just boolSort) p)
    go _ (PAll   bs p)    = PAll   bs <$> withExtendedEnv bs (go (Just boolSort) p)
                            -- NOPROP do bs' <- mapM defunc bs
                            -- NOPROP return $ PExist bs p'
    -- NOPROP do bs' <- mapM defunc bs
    -- NOPROP p'  <- withExtendedEnv bs $ go (Just boolSort) p
    -- NOPROP return $ PAll bs' p'
    go _ (PAtom r e1 e2)  = PAtom r <$> go Nothing e1 <*> go Nothing e2
    go _ PGrad            = return PGrad
    go _ (ELam x ex)      = (dfLam <$> get) >>= defuncELam x ex
    go _ e                = errorstar ("defunc Pred: " ++ show e)



defuncELam :: (Symbol, Sort) -> Expr -> Bool -> DF Expr
defuncELam (x, s) e aeq | aeq
  = do y  <- freshSym
       de <- defuncExpr $ subst1 e (x, EVar y)
       logLam (y, s) (subst1 e (x, EVar y))
       return $ normalizeLams $ ELam (y, s) de
defuncELam xs e _
  = ELam xs <$> defuncExpr e


maxLamArg :: Int
maxLamArg = 7

-- NIKI TODO: allow non integer lambda arguments
-- sorts = [setSort intSort, bitVecSort intSort, mapSort intSort intSort, boolSort, realSort, intSort]
makeLamArg :: Sort -> Int  -> Symbol
makeLamArg _ = intArgName



--------------------------------------------------------------------------------

makeAxioms :: DF [Expr]
makeAxioms = do
  alphaFlag <- dfAEq <$> get
  betaFlag  <- dfBEq <$> get
  asyms     <- makeSymbolAxioms
  asb       <- if betaFlag  then withNoLambdaNormalization $ withNoEquivalence makeBetaAxioms   else return []
  asa       <- if alphaFlag then withNoLambdaNormalization $ withNoEquivalence makeAlphaAxioms  else return []
  return (asa ++ asb ++ asyms)

--------------------------------------------------------------------------------
-- | Symbols -------------------------------------------------------------------
--------------------------------------------------------------------------------

logSym :: SymConst -> DF ()
logSym x = modify $ \s -> s{dfSyms = x:dfSyms s}

makeSymbolAxioms :: DF [Expr]
makeSymbolAxioms = ((map go . dfSyms) <$> get) >>= mapM txCastedExpr
  where
    go (SL s) = EEq (makeGenStringLen $ symbolExpr $ SL s) (expr (T.length s) `ECst` intSort)

symbolExpr :: SymConst -> Expr
symbolExpr = EVar . symbol

makeStringLen :: Expr -> Expr
makeStringLen = EApp (EVar Thy.strLen)

makeGenStringLen :: Expr -> Expr
makeGenStringLen e
 = EApp (ECst (EVar Thy.genLen) (FFunc strSort intSort)) (ECst e strSort)
   `ECst` intSort

--------------------------------------------------------------------------------
-- |Alpha Equivalence ----------------------------------------------------------
--------------------------------------------------------------------------------

logLam :: (Symbol, Sort) -> Expr -> DF Expr
logLam xs bd = do
  aEq <- dfAEq <$> get
  modify $ \s -> s{dfRedex = closeLams xs <$> dfRedex s}
  modify $ \s -> s{dfLams  = closeLams xs <$> dfLams s}
  let e = ELam xs bd
  when aEq (modify $ \s -> s { dfLams = e : dfLams s })
  return $ normalizeLams e

closeLams :: (Symbol, Sort) -> Expr -> Expr
closeLams (x, s) e = if x `elem` syms e then PAll [(x, s)] e else e

makeAlphaAxioms :: DF [Expr]
makeAlphaAxioms = do
  lams <- dfLams <$> get
  mapM defuncExpr $ concatMap makeAlphaEq $ L.nub (normalizeLams <$> lams)



makeAlphaEq :: Expr -> [Expr]
makeAlphaEq e = go e ++ go' e
  where
    go ee
      = makeEqForAll ee (normalize ee)
    go' ee@(ELam (x, s) e)
      = [makeEq ee ee'
         | (i, ee') <- map (\j -> normalizeLamsFromTo j (ELam (x, s) e)) [1..maxLamArg-1]
         , i <= maxLamArg ]
    go' _
      = []


--------------------------------------------------------------------------------
-- | Normalizations ------------------------------------------------------------
--------------------------------------------------------------------------------

-- head normal form

normalize :: Expr -> Expr
normalize = snd . go
  where
    go (ELam (y, sy) e) = let (i', e') = go e
                              y'      = makeLamArg sy i'
                          in (i'+1, ELam (y', sy) (e' `subst1` (y, EVar y')))
    go (EApp e e2)
      |  (ELam (x, _) bd) <- unECst e
                        = let (i1, e1') = go bd
                              (i2, e2') = go e2
                          in (max i1 i2, e1' `subst1` (x, e2'))
    go (EApp e1 e2)     = let (i1, e1') = go e1
                              (i2, e2') = go e2
                          in (max i1 i2, EApp e1' e2')
    go (ECst e s)       = mapSnd (`ECst` s) (go e)
    go (PAll bs e)      = mapSnd (PAll bs)  (go e)
    go e                = (1, e)

    unECst (ECst e _) = unECst e
    unECst e          = e

-- normalize lambda arguments

normalizeLams :: Expr -> Expr
normalizeLams e = snd $ normalizeLamsFromTo 1 e

normalizeLamsFromTo :: Int -> Expr -> (Int, Expr)
normalizeLamsFromTo i   = go
  where
    go (ELam (y, sy) e) = let (i', e') = go e
                              y'      = makeLamArg sy i'
                          in (i'+1, ELam (y', sy) (e' `subst1` (y, EVar y')))
    go (EApp e1 e2)     = let (i1, e1') = go e1
                              (i2, e2') = go e2
                          in (max i1 i2, EApp e1' e2')
    go (ECst e s)       = mapSnd (`ECst` s) (go e)
    go (PAll bs e)      = mapSnd (PAll bs) (go e)
    go e                = (i, e)

-------------------------------------------------------------------------------
--------  Beta Equivalence  ---------------------------------------------------
-------------------------------------------------------------------------------

logRedex :: Expr -> DF ()
logRedex e@(EApp f _)
  | (ELam _ _) <- stripCasts f
  = do bEq <- dfBEq <$> get
       when bEq (modify $ \s -> s{dfRedex = e:dfRedex s})
logRedex _
  = return ()


makeBetaAxioms :: DF [Expr]
makeBetaAxioms = do
  red <- dfRedex <$> get
  concat <$> mapM makeBetaEq red


makeBetaEq :: Expr -> DF [Expr]
makeBetaEq e = mapM defuncExpr $ makeEqForAll (normalizeLams e) (normalize e)


makeEq :: Expr -> Expr -> Expr
makeEq e1 e2
  | e1 == e2  = PTrue
  | otherwise = EEq e1 e2


makeEqForAll :: Expr -> Expr -> [Expr]
makeEqForAll e1 e2 =
  [ makeEq (closeLam su e1') (closeLam su e2') | su <- instantiate xs]
  where
    (xs1, e1') = splitPAll [] e1
    (xs2, e2') = splitPAll [] e2
    xs         = L.nub (xs1 ++ xs2)

    closeLam ((x, (y,s)):su) e = ELam (y,s) (subst1 (closeLam su e) (x, EVar y))
    closeLam []              e = e

    splitPAll acc (PAll xs e) = splitPAll (acc ++ xs) e
    splitPAll acc e           = (acc, e)

instantiate :: [(Symbol, Sort)] -> [[(Symbol, (Symbol,Sort))]]
instantiate [] = [[]]
instantiate xs = L.foldl' (\acc x -> combine (instOne x) acc) [] xs
  where
    instOne (x, s) = [(x, (makeLamArg s i, s)) | i <- [1..maxLamArg]]
    combine xs []  = [[x] | x <- xs]
    combine xs acc = concat [(x:) <$> acc | x <- xs]

--------------------------------------------------------------------------------
-- | Numeric Overloading  ------------------------------------------------------
--------------------------------------------------------------------------------
txnumOverloading :: Expr -> Expr
txnumOverloading = mapExpr go
  where
    go (ETimes e1 e2)
      | exprSort e1 == FReal, exprSort e2 == FReal
      = ERTimes e1 e2
    go (EDiv   e1 e2)
      | exprSort e1 == FReal, exprSort e2 == FReal
      = ERDiv   e1 e2
    go e
      = e

txStr :: Bool -> Expr -> DF Expr
txStr flag e
  | flag      = return (mapExpr goStr e)
  | otherwise = mapMExpr goNoStr e
  where
    goStr e@(EApp _ _)
      | Just a <- isStringLen e
      = makeStringLen a
    goStr e
       = e
    goNoStr (ESym s)
      = logSym s >> return (symbolExpr s)
    goNoStr e
      = return e


isStringLen :: Expr -> Maybe Expr
isStringLen e
  = case stripCasts e of
     EApp (EVar f) a | Thy.genLen == f && hasStringArg e
                     -> Just a
     _               -> Nothing
  where
    hasStringArg (ECst e _) = hasStringArg e
    hasStringArg (EApp _ a) = isString $ exprSort a
    hasStringArg _          = False

-------------------------------------------------------------------------------
--------  Extensionality  -----------------------------------------------------
-------------------------------------------------------------------------------

txExtensionality :: Expr -> Expr
txExtensionality = mapExpr' go
  where
    go (EEq e1 e2)
      | FFunc _ _ <- exprSort e1, FFunc _ _ <- exprSort e2
      = mkExFunEq e1 e2
    go e
      = e

mkExFunEq :: Expr -> Expr -> Expr
mkExFunEq e1 e2 = PAnd [PAll (zip xs ss)
                             (EEq
                                (ECst (eApps e1' es) s)
                                (ECst (eApps e2' es) s))
                       , EEq e1 e2]
  where
    es      = zipWith (\x s -> ECst (EVar x) s) xs ss
    xs      = (\i -> symbol ("local_fun_arg" ++ show i)) <$> [1..length ss]
    (s, ss) = splitFun [] s1
    s1      = exprSort e1

    splitFun acc (FFunc s ss) = splitFun (s:acc) ss
    splitFun acc s            = (s, reverse acc)

    e1' = ECst e1 s1
    e2' = ECst e2 s1



--------------------------------------------------------------------------------
-- | Containers defunctionalization --------------------------------------------
--------------------------------------------------------------------------------

instance (Defunc (c a), TaggedC c a) => Defunc (GInfo c a) where
  defunc fi = do
    cm'    <- defunc $ cm    fi
    -- NOPROP ws'    <- defunc $ ws    fi
    setBinds $ mconcat ((senv <$> M.elems (cm fi)) ++ (wenv <$> M.elems (ws fi)))
    -- NOPROP gLits' <- defunc $ gLits fi
    -- NOPROP dLits' <- defunc $ dLits fi
    bs'    <- defunc $ bs    fi
    quals' <- defunc $ quals fi
    axioms <- makeAxioms
    return $ fi { cm      = cm'
                -- , ws      = ws'
                -- NOPROP , gLits   = gLits'
                -- NOPROP , dLits   = dLits'
                , bs      = bs'
                , quals   = quals'
                , asserts = axioms
                }

instance Defunc (SimpC a) where
  defunc sc = do crhs' <- defunc $ _crhs sc
                 return $ sc {_crhs = crhs'}

-- NOPROP instance Defunc (WfC a)   where
  -- NOPROP defunc wf = do wrft' <- defunc $ wrft wf
                 -- NOPROP return $ wf {wrft = wrft'}

instance Defunc Qualifier where
  defunc q = -- NOPROP qParams' <- defunc $ qParams q
                withExtendedEnv (qParams q) $ withNoEquivalence $ do
                  qBody'   <- defunc $ qBody   q
                  return    $ q {{- NOPROP qParams = qParams', -} qBody = qBody'}

instance Defunc SortedReft where
  defunc (RR s r) = RR s <$> defunc r

instance Defunc (Symbol, SortedReft) where
  defunc (x, RR s (Reft (v, e)))
    = (x,) <$> defunc (RR s (Reft (x, subst1 e (v, EVar x))))

instance Defunc Reft where
  defunc (Reft (x, e)) = Reft . (x,) <$> defunc e

-- instance Defunc (a, Sort, c) where
--   defunc (x, y, z) = (x, , z) <$> defunc y

-- instance Defunc (a, Sort) where
--  defunc (x, y) = (x, ) <$> defunc y

instance Defunc a => Defunc (SEnv a) where
  defunc = mapMSEnv defunc

instance Defunc BindEnv   where
  defunc bs = do dfbs <- dfbenv <$> get
                 let f (i, xs) = if i `memberIBindEnv` dfbs
                                       then  (i,) <$> defunc xs
                                       else  return (i, xs) -- NOPROP (i,) <$> matchSort xs
                 mapWithKeyMBindEnv f bs
   where
    -- The refinement cannot be elaborated thus defunc-ed because
    -- the bind does not appear in any contraint,
    -- thus unique binders does not perform properly
    -- The sort should be defunc, to ensure same sort on double binders
    -- NOPROP matchSort (x, RR s r) = ((x,) . (`RR` r)) <$> defunc s

instance Defunc a => Defunc [a] where
  defunc = mapM defunc

instance (Defunc a, Eq k, Hashable k) => Defunc (M.HashMap k a) where
  defunc m = M.fromList <$> mapM (secondM defunc) (M.toList m)

type DF    = State DFST

type DFEnv = SEnv Sort

data DFST
  = DFST { fresh   :: !Int
         , dfenv   :: !DFEnv
         , dfbenv  :: !IBindEnv
         , dfLam   :: !Bool   -- ^ normalize lams
         , dfExt   :: !Bool   -- ^ enable extensionality axioms
         , dfAEq   :: !Bool   -- ^ enable alpha equivalence axioms
         , dfBEq   :: !Bool   -- ^ enable beta equivalence axioms
         , dfNorm  :: !Bool   -- ^ enable normal form axioms
         , dfHO    :: !Bool   -- ^ allow higher order thus defunctionalize
         , dfLNorm :: !Bool
         , dfStr   :: !Bool   -- ^ string interpretation
         , dfLams  :: ![Expr] -- ^ lambda expressions appearing in the expressions
         , dfRedex :: ![Expr] -- ^ redexes appearing in the expressions
         , dfLog   :: !String
         , dfSyms  :: ![SymConst] -- symbols in the refinements
         }

makeInitDFState :: Config -> SInfo a -> DFST
makeInitDFState cfg si
  = DFST { fresh   = 0
         , dfenv   = fromListSEnv xs
         , dfbenv  = mempty
         , dfLam   = True
         , dfExt   = extensionality   cfg
         , dfAEq   = alphaEquivalence cfg
         , dfBEq   = betaEquivalence  cfg
         , dfNorm  = normalForm       cfg
         , dfHO    = allowHO cfg  || defunction cfg
         , dfLNorm = True
         -- INVARIANT: lambads and redexes are not defunctionalized
         , dfLams  = []
         , dfRedex = []
         , dfSyms  = []
         , dfLog   = ""
         , dfStr   = stringTheory cfg
         }
  where
    xs = symbolSorts cfg si ++ concat [ [(x,s), (y,s)] | (_, x, RR s (Reft (y, _))) <- bindEnvToList $ bs si]


setBinds :: IBindEnv -> DF ()
setBinds e = modify $ \s -> s{dfbenv = e}


_writeLog :: String -> DF ()
_writeLog str = modify $ \s -> s{dfLog =  dfLog s ++ "\n" ++ str}

withExtendedEnv ::  [(Symbol, Sort)] -> DF a -> DF a
withExtendedEnv bs act = do
  env <- dfenv <$> get
  let env' = foldl (\env (x, t) -> insertSEnv x t env) env bs
  modify $ \s -> s{dfenv = env'}
  r <- act
  modify $ \s -> s{dfenv = env}
  return r

withNoLambdaNormalization :: DF a -> DF a
withNoLambdaNormalization act = do
  dfLNorm <- dfLam <$> get
  modify $ \s -> s{dfLam = False}
  r <- act
  modify $ \s -> s{dfLam = dfLNorm}
  return r

withNoEquivalence :: DF a -> DF a
withNoEquivalence act = do
  aEq <- dfAEq <$> get
  bEq <- dfBEq <$> get
  modify $ \s -> s{dfAEq = False, dfBEq = False}
  r <- act
  modify $ \s -> s{dfAEq = aEq,   dfBEq = bEq}
  return r

freshSym :: DF Symbol
freshSym = do
  n  <- fresh <$> get
  modify $ \s -> s{fresh = n + 1}
  return $ intSymbol "lambda_fun_" n

-- RJ: according to https://github.com/ucsd-progsys/liquid-fixpoint/commit/d8b742b29c8a892fc947eb90fe6eb949207f65cb
-- the `Visitor.mapExpr` "diverges"?
mapExpr' :: (Expr -> Expr) -> Expr -> Expr
mapExpr' f = go
  where
    go (ELam bs e)     = f (ELam bs (go e))
    go (ECst e s)      = f (ECst (go e) s)
    go (EApp e1 e2)    = f (EApp (go e1) (go e2))
    go e@(ESym _)      = f e
    go e@(ECon _)      = f e
    go e@(EVar _)      = f e
    go (ENeg e)        = f $ ENeg (go e)
    go (EBin b e1 e2)  = f $ EBin b (go e1) (go e2)
    go (EIte e e1 e2)  = f $ EIte (go e) (go e1) (go e2)
    go (ETAbs e t)     = f $ ETAbs (go e) t
    go (ETApp e t)     = f $ ETApp (go e) t
    go (PAnd es)       = f $ PAnd $ map go es
    go (POr es)        = f $ POr  $ map go es
    go (PNot e)        = f $ PNot $ go e
    go (PImp e1 e2)    = f $ PImp (go e1) (go e2)
    go (PIff e1 e2)    = f $ PIff (go e1) (go e2)
    go (PAtom a e1 e2) = f $ PAtom a (go e1) (go e2)
    go (PAll bs e)     = f $ PAll bs   $  go e
    go (PExist bs e)   = f $ PExist bs $ go e
    go e@(PKVar _ _ )  = f e
    go e@PGrad         = f e
