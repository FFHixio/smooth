{-|
A module for higher-order, higher-dimensional forward-mode
automatic differentiation a la
<http://conal.net/blog/posts/higher-dimensional-higher-order-derivatives-functionally>
-}

{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies, FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances, IncoherentInstances #-}

module SelfContained.Fwd where

import Prelude
import Control.Arrow
import Control.Applicative (liftA2)
import Control.Monad (join)

type a :-* b = a -> b
data a :> b = D b (a :-* (a :> b))
type a :~> b = a -> (a :> b)

class VectorSpace v s | v -> s where
  zeroV   :: v              -- the zero vector
  (*^)    :: s -> v -> v    -- scale a vector
  (^+^)   :: v -> v -> v    -- add vectors
  negateV :: v -> v         -- additive inverse

instance Num a => VectorSpace a a where
  zeroV = 0
  (*^) = (*)
  (^+^) = (+)
  negateV = negate

instance VectorSpace v s => VectorSpace (a -> v) s where
  zeroV   = pure   zeroV
  (*^) s  = fmap   (s *^)
  (^+^)   = liftA2 (^+^)
  negateV = fmap   negateV

instance VectorSpace u s => VectorSpace (a :> u) (a :> s) where
  zeroV = D zeroV (\_ -> zeroV)
  s@(D s0 s') *^ x@(D x0 x') = D (s0 *^ x0) (\d -> (s *^ x' d) ^+^ (s' d *^ x))
  D a a' ^+^ D b b' = D (a ^+^ b) (\d -> a' d ^+^ b' d)
  negateV (D a a') = D (negateV a) (negateV a')

instance (VectorSpace u1 s, VectorSpace u2 s) => VectorSpace (u1, u2) s where
  zeroV = (zeroV, zeroV)
  s *^ (x, y) = (s *^ x, s*^ y)
  (x, y) ^+^ (x', y') = (x ^+^ x', y ^+^ y')
  negateV (x, y) = (negateV x, negateV y)

dConst :: VectorSpace b s => b -> a :> b
dConst b = D b (const dZero)

dZero :: VectorSpace b s => a :> b
dZero = dConst zeroV

dId :: VectorSpace u s => u :~> u
dId u = D u (\du -> dConst du)

linearD :: VectorSpace v s => (u :-* v) -> (u :~> v)
linearD f u = D (f u) (\du -> dConst (f du))

fstD :: VectorSpace a s => (a,b) :~> a
fstD = linearD fst

sndD :: VectorSpace b s => (a,b) :~> b
sndD = linearD snd

pairD :: g :~> a -> g :~> b -> g :~> (a, b)
pairD f g x = D (fx, gx) (pairD f'x g'x) where
  D fx f'x = f x
  D gx g'x = g x

dap1 :: VectorSpace b s => a :~> b -> g :~> a -> g :~> b
dap1 f = (f @.)

dap2 :: VectorSpace c s => (a, b) :~> c -> g :~> a -> g :~> b -> g :~> c
dap2 f x y = f @. pairD x y

square :: Num a => a :~> a
square x = dId x ^ 2

cube :: Num a => a :~> a
cube x = dId x ^ 3

dMult :: Num a => g :~> a -> g :~> a -> g :~> a
dMult f g x = f x * g x

square' :: Num a => g :~> a -> g :~> a
square' x = dMult x x

cube' :: Num a => g :~> a -> g :~> a
cube' x = x^3

absD :: Num a => a :~> a
absD x = abs (dId x)

getValue :: a :> b -> b
getValue (D x dx) = x

getDeriv :: a :> b -> a :~> b
getDeriv (D x dx) = dx

getDerivTower :: Num a => a :> b -> [b]
getDerivTower (D x dx) = x : getDerivTower (dx 1)

instance Num b => Num (a->b) where
  fromInteger = pure . fromInteger
  (+)         = liftA2 (+)
  (*)         = liftA2 (*)
  negate      = fmap negate
  abs         = fmap abs
  signum      = fmap signum

instance Num b => Num (a:>b) where
  fromInteger               = dConst . fromInteger
  D u0 u' + D v0 v'         = D (u0 + v0) (u' + v')
  D u0 u' - D v0 v'         = D (u0 - v0) (u' - v')
  u@(D u0 u') * v@(D v0 v') =
    D (u0 * v0) (\da -> u * v' da + u' da * v)
  abs u@(D u0 u') = D (abs u0) (\da -> signum u * u' da)
  -- not totally accurate for signum here, it should blow up at 0...
  signum (D u u') = D (signum u) 0

instance Fractional b => Fractional (a:>b) where
  recip = lift1 recip (\u -> - recip (u^2))
  fromRational = dConst . fromRational

instance Fractional b => Fractional (a -> b) where
  recip = fmap recip
  fromRational = pure . fromRational

-- Borrowed from
-- http://hackage.haskell.org/package/ad-4.3.6/docs/src/Numeric.AD.Internal.Forward.Double.html#ForwardDouble
instance Floating b => Floating (a :> b) where
  pi = dConst pi
  log = lift1 log recip
  exp = exp >-< exp
  sin      = lift1 sin cos
  cos      = lift1 cos $ negate . sin
  tan      = lift1 tan $ recip . join (*) . cos
  asin     = lift1 asin $ \x -> recip (sqrt (1 - join (*) x))
  acos     = lift1 acos $ \x -> negate (recip (sqrt (1 - join (*) x)))
  atan     = lift1 atan $ \x -> recip (1 + join (*) x)
  sinh     = lift1 sinh cosh
  cosh     = lift1 cosh sinh
  tanh     = lift1 tanh $ recip . join (*) . cosh
  asinh    = lift1 asinh $ \x -> recip (sqrt (1 + join (*) x))
  acosh    = lift1 acosh $ \x -> recip (sqrt (join (*) x - 1))
  atanh    = lift1 atanh $ \x -> recip (1 - join (*) x)

instance Floating b => Floating (a -> b) where
  pi = pure pi
  log = fmap log
  exp = fmap exp
  sin = fmap sin
  cos = fmap cos
  tan = fmap tan
  asin = fmap asin
  acos = fmap acos
  atan = fmap atan
  sinh = fmap sinh
  cosh = fmap cosh
  tanh = fmap tanh
  asinh = fmap asinh
  acosh = fmap acosh
  atanh = fmap atanh

lift1 :: Num b => (b -> b) -> ((a :> b) -> a :> b) -> (a :> b) -> a :> b
lift1 f f' u@(D u0 u') = D (f u0) (\da -> u' da * f' u)

(>-<) :: VectorSpace u s =>
    (u -> u) -> ((a :> u) -> (a :> s)) -> (a :> u) -> (a :> u)
f >-< f' = \u@(D u0 u') -> D (f u0) (\da -> f' u *^ u' da)

-- Fixed compared to Conal Elliot's version!
(@.) :: VectorSpace c s => (b :~> c) -> (a :~> b) -> (a :~> c)
(f @. g) a0 = D c0 (linCompose c' b')
  where
    D b0 b' = g a0
    D c0 c' = f b0

linCompose :: VectorSpace c s => (b :~> c) -> (a :~> b) -> (a :~> c)
linCompose f g a0 = D c0 (\x -> linCompose c' g x ^+^ linCompose f b' x)
  where
    D b0 b' = g a0
    D c0 c' = f b0

mult4Example :: Int -> Double
mult4Example n = getDerivTower ((((*2) dId) @. ((*2) dId)) (1)) !! n

exampleAbsDiff :: Double
exampleAbsDiff = getDerivTower (absD 0) !! 1

example2 :: Double
example2 = getDerivTower ((\x -> abs (x ^ 2)) dId 2) !! 2

example3 :: Double
example3 = getDerivTower ((\x -> abs x) dId (sqrt 2)) !! 1