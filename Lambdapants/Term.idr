module Lambdapants.Term

||| In the lambda calculus, a term is one of three things:
|||   * A variable is a term;
|||   * Application of two terms is a term; and
|||   * A lambda abstraction is a term.
|||
||| Nothing else is a term. Application is left-associative, so the term
||| `(s t u)` is the same as `(s t) u`. One often omits outermost parentheses.
||| In abstractions, the body extends as far to the right as possible.
public export 
data Term : Type where
  ||| Variable
  Var : String -> Term
  ||| Lambda abstraction
  Lam : String -> Term -> Term
  ||| Application
  App : Term -> Term -> Term

export 
Eq Term where
  (Var a)   == (Var b)   = a == b
  (Lam x t) == (Lam y u) = x == y && t == u
  (App t u) == (App v w) = t == v && u == w
  _         == _         = False

export 
Show Term where
  show (Var v)   = "Var "  ++ show v
  show (App t u) = "App (" ++ show t ++ ") ("
                           ++ show u ++ ")"
  show (Lam x t) = "Lam "  ++ show x ++ " ("
                           ++ show t ++ ")"

mutual
  lam : Term -> String
  lam (Lam x t) = "\x03BB" ++ x ++ "." ++ lam t
  lam term = app term

  app : Term -> String
  app (App t u) = app t ++ " " ++ pretty u
  app term = pretty term

  ||| Translate the given term to a pretty-printed string representation.
  export
  pretty : Term -> String
  pretty term =
    case term of
         Lam _ _ => "(" ++ lam term ++ ")"
         App _ _ => "(" ++ app term ++ ")"
         Var var => var

||| Return a list of all variables which appear free in the term *t*.
export total
freeVars : (t : Term) -> List String
freeVars (Var v)   = [v]
freeVars (Lam v t) = delete v (freeVars t)
freeVars (App t u) = freeVars t `union` freeVars u

||| Return a boolean to indicate whether the variable *v* appears free in the
||| term *t*.
total
isFreeIn : (v : String) -> (t : Term) -> Bool
isFreeIn var term = elem var (freeVars term)

||| Return all variables (free and bound) which appears in the term *t*.
export total
vars : (t : Term) -> List String
vars (Var v)   = [v]
vars (Lam v t) = v :: vars t
vars (App t u) = vars t `union` vars u

||| Return a boolean to indicate whether the term is reducible.
export total
isRedex : Term -> Bool
isRedex (App (Lam _ _) _) = True
isRedex (App e1 e2)       = isRedex e1 || isRedex e2
isRedex (Lam _ e1)        = isRedex e1
isRedex _                 = False

another : String -> String
another name =
  case unpack name of
       (c :: [])      => if 'a' <= c && c < 'z'
                            then pack [succ c]
                            else pack (c :: '0' :: [])
       (b :: c :: []) => if '0' <= c && c < '9'
                            then pack (b :: succ c :: [])
                            else name ++ "'"
       _              => name ++ "'"

fresh : Term -> String -> String
fresh expr = diff where
  names : List String
  names = freeVars expr
  diff : String -> String
  diff x = let x' = another x in if x' `elem` names then diff x' else x'

alphaRename : String -> String -> Term -> Term
alphaRename from to term =
  case term of
       (Var v)     => Var (if v == from then to else v)
       (App e1 e2) => App (alphaRename from to e1) (alphaRename from to e2)
       (Lam x e)   => Lam (if x == from then to else x) (alphaRename from to e)

||| Perform the substitution `s[ n := e ]`.
||| @n - a variable to substitute for
||| @e - the term that the variable *n* will be replaced with
||| @s - the original term
export
substitute : (n : String) -> (e : Term) -> (s : Term) -> Term
substitute var expr = subst where
  subst : Term -> Term
  subst (Var v)     = if var == v then expr else Var v
  subst (App e1 e2) = App (subst e1) (subst e2)
  subst (Lam x e) with (x == var)
    | True  = Lam x e -- If the variable we are susbstituting for is re-bound
    | False = if x `isFreeIn` expr
                 then let x' = fresh expr x
                          e' = alphaRename x x' e in
                      Lam x' (subst e')
                 else Lam x  (subst e)

||| Apply beta reduction to the expression *e* to derive a new term. This
||| function is defined in terms of *substitute*.
export
reduce : (e : Term) -> Term
reduce (App (Lam v t) s) = substitute v s t
reduce (Lam v t) = Lam v (reduce t)
reduce (App t u) = if isRedex t
                      then App (reduce t) u
                      else App t (reduce u)
reduce term = term

||| De Bruijn-indexed intermediate representation for comparing terms under the
||| notion of alpha equivalence.
data Indexed : Type where
  ||| Bound variable (depth indexed)
  Bound : Nat -> Indexed
  ||| Free variable
  Free  : String -> Indexed
  ||| Application
  IApp  : Indexed -> Indexed -> Indexed
  ||| Lambda abstraction
  ILam  : Indexed -> Indexed

Show Indexed where
  show (Bound n)  = "Bound " ++ show n
  show (Free v)   = "Free "  ++ show v
  show (IApp t u) = "IApp (" ++ show t ++ ") ("
                             ++ show u ++ ")"
  show (ILam t)   = "ILam (" ++ show t ++ ")"

Eq Indexed where
  (Bound m)  == (Bound n)  = m == n
  (Free v)   == (Free w)   = v == w
  (IApp t u) == (IApp v w) = t == v && u == w
  (ILam t)   == (ILam u)   = t == u
  _          == _          = False

||| Translate the term *t* to a canonical De Bruijn (depth-indexed) form.
total
toIndexed : (t : Term) -> Indexed
toIndexed = toIx []
where
  toIx : List String -> Term -> Indexed
  toIx bound (Var x)   = maybe (Free x) Bound (elemIndex x bound)
  toIx bound (App t u) = IApp (toIx bound t) (toIx bound u)
  toIx bound (Lam x t) = ILam (toIx (x :: bound) t)

||| Return a boolean to indicate whether two terms are alpha equivalent; that
||| is, whether one can be converted into the other purely by renaming of bound
||| variables.
export total
alphaEq : Term -> Term -> Bool
alphaEq t u = toIndexed t == toIndexed u