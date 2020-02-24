{-# LANGUAGE FlexibleInstances, FlexibleContexts #-}

module Types.SmoothBool where

import qualified Prelude
import Prelude hiding (Real, (&&), (||), not, max, min, Ord (..), (^))
import FwdMode ((:~>), fstD, sndD, getDerivTower, getValue, (@.), pow')
import FwdMode
import FwdPSh
import Interval (Interval (..))
import Data.List (intercalate)
import RealExpr (runPoint)
import qualified Rounded as R
import qualified Expr

-- SBool = quotient of the reals by the smooth equivalence relation
-- x ~ y :=   x = y \/ (x < 0 /\ y < 0) \/ (x > 0 /\ y > 0)
newtype SBool g = SBool (DReal g)

instance Show (SBool ()) where
  show (SBool (R x)) = go . runPoint $ getValue x where
    go (Interval a b : xs)
      | a Prelude.> R.zero = "true"
      | b Prelude.< R.zero = "false"
      | otherwise = "?\n" ++ go xs

true :: SBool g
true = SBool 1

false :: SBool g
false = SBool (-1)

not :: SBool g -> SBool g
not (SBool x) = SBool (- x)

infixr 3 &&
(&&) :: SBool g -> SBool g -> SBool g
SBool x && SBool y = SBool (x + y - sqrt (x^2 + y^2))
-- SBool (R x) && SBool (R y) = SBool (R (min x y))

infixr 2 ||
(||) :: SBool g -> SBool g -> SBool g
SBool x || SBool y = SBool (x + y + sqrt (x^2 + y^2))
-- SBool (R x) || SBool (R y) = SBool (R (max x y))

positive :: DReal g -> SBool g
positive = SBool

infix 4 <
(<) :: DReal g -> DReal g -> SBool g
x < y = SBool (y - x)

infix 4 >
(>) :: DReal g -> DReal g -> SBool g
x > y = SBool (x - y)

-- Not really the right home for this function.
infixr 8 ^
(^) :: DReal g -> Int -> DReal g
R x ^ k = R (pow x k)

deriv :: Additive g => (DReal :=> DReal) g -> DReal g -> DReal g
deriv f (R x) = R $ fwd_deriv1 f x 1

-- Describe a real number by a predicate saying what it means
-- to be less than it.
-- x < dedekind_cut P  iff P x
dedekind_cut :: Additive g => (DReal :=> SBool) g -> DReal g
dedekind_cut (ArrD f) = R (FwdPSh.newton_cut' (let SBool (R b) = f fstD (R sndD) in b))

forall01 :: Additive g => (DReal :=> SBool) g -> SBool g
forall01 (ArrD f) = positive (R (FwdPSh.min01' (let SBool (R b) = f fstD (R sndD) in b)))

exists01 :: Additive g => (DReal :=> SBool) g -> SBool g
exists01 (ArrD f) = positive (R (FwdPSh.max01' (let SBool (R b) = f fstD (R sndD) in b)))

dedekind_cubert :: Additive g => DReal g -> DReal g
dedekind_cubert z = dedekind_cut (ArrD (\wk x -> x < 0 || x^3 < dmap wk z))

testBSqrt :: CPoint Real -> [CPoint Real]
testBSqrt z = let R f = dedekind_cut (ArrD (\c x -> x < 0 || x^2 < R c)) in
    getDerivTower f z

testBCubert :: CPoint Real -> [CPoint Real]
testBCubert z = let R f = dedekind_cut (ArrD (\c x -> x^3 < R c)) in
    getDerivTower f z

-- Only working via bisection, so derivatives must not be good.
testOpt :: () :~> Real
testOpt = FwdPSh.newton_cut (\q -> FwdPSh.max01 (\x -> FwdPSh.min01 (\y -> pow (wkn x - y) 2 - wkn (wkn q))))

testOptHelp :: CPoint Real -> [CPoint Real]
testOptHelp = getDerivTower' (\q -> FwdPSh.max01 (\x -> FwdPSh.min01 (\y -> pow (wkn x - y) 2 - wkn (wkn q))))

-- Should be -1, but it doesn't converge
testOptHelpExample :: CPoint Real
testOptHelpExample = testOptHelp 0 !! 1

testOpt2 :: () :~> Real
testOpt2 = FwdPSh.max01 (\x -> FwdPSh.min01 (\y -> pow (wkn x - y) 2))

testOpt2Help :: CPoint Real -> [CPoint Real]
testOpt2Help = getDerivTower' (\x -> FwdPSh.newton_cut (\q -> wkn x - q))

simplerMaximization :: CPoint Real -> [CPoint Real]
simplerMaximization = getDerivTower' (\r ->
  FwdPSh.newton_cut (\q -> FwdPSh.max01 (\x -> min (wkn (wkn r) - x) (x - wkn q))))

-- Still not converging, but it should
simplerMaximizationExample :: CPoint Real
simplerMaximizationExample = simplerMaximization 0.5 !! 1

simplerMaximizationPart :: CPoint Real -> [CPoint Real]
simplerMaximizationPart = getDerivTower' (\q -> FwdPSh.argmax01 (\x -> min1 (0.5 - x) (x - wkn q)))
  where min1 x y = (x + y - sqrt (pow x 2 + pow y 2))

-- Gives the wrong answer
simplerMaximizationPartExample :: CPoint Real
simplerMaximizationPartExample = simplerMaximizationPart 0.4 !! 1

tester :: (Real, (Real, Real)) :~> Real
tester = fwdSecondDer ((\q-> pow q 2) dId)

-- Still not returning 0 when it should!
evalTester :: () :~> Real
evalTester = let f = ((\q-> pow q 2) dId) in
  let f' = fwdDer f in
  fwdDer f' @. pairD (pairD 0 1) (pairD 0 0)

tester1 :: CPoint Real -> [CPoint Real]
tester1 = let f = ((\q-> pow q 2) dId) in
  getDerivTower (fwdDer f @. pairD 0 1)

-- tester1 x !! n = 2.0
-- when n >= 1
-- This is BROKEN!
-- should be 0, because it is the constant 0 function.
-- The error is in (@. dId)!

tester2 :: CPoint Real -> [CPoint Real]
tester2 = let f = ((\q-> pow q 3) dId) in
  getDerivTower f

-- When I look at the derivatives for f(x) = x^3, I find that
-- f^(3)(dx1, dx2, dx3) = 6 * dx1^3
-- rather than 6 * dx1 * dx2 * dx3


-- !!! (pow q 2) dId is not the same as pow' 2!!!
-- pow q 2 = pow' 2 @. dId
-- i.e., f @. dId =/= f

tester3 :: CPoint Real -> [CPoint Real]
tester3 = let f = (square'' @. dId) in
  getDerivTower f

bloat :: a -> [[a]] -> [[[a]]]
bloat x  []      = [[[x]]]
bloat x (xs:xss) = ((x:xs):xss) : map (xs:) (bloat x xss)

partitions :: [a] -> [[[a]]]
partitions  []    = [[]]
partitions (x:xs) = concatMap (bloat x) (partitions xs)