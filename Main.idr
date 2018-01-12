module Main

import Effect.Readline
import Effect.State
import Effect.StdIO
import Effects
import Lambdapants.Command
import Lambdapants.Command.Parser
import Lambdapants.Term
import Lambdapants.Term.Parser
import Lambdapants.Term.Reduction
import Lightyear.Strings

ansiPut : String -> String -> Eff () [STDIO]
ansiPut code str = do
  putStr ("\ESC[" ++ code ++ "m")
  putStr str
  putStr "\ESC[0m"

||| Return the Church encoded term corresponding to the provided number.
churchEncoded : Nat -> Term
churchEncoded n = Lam "f" (Lam "x" nat) where
  nat : Term
  nat = foldr apply (Var "x") (take n (repeat (Term.App (Var "f"))))

stdEnv : Environment
stdEnv = catMaybes (map f
  [ ("plus"    , "\\m.\\n.\\f.\\x.m f (n f x)")
  , ("succ"    , "\\n.\\f.\\x.f (n f x)")
  , ("pred"    , "\\n.\\f.\\x.n (\\g.\\h.h (g f)) (\\u.x) (\\u.u)")
  , ("mult"    , "\\m.\\n.\\f.m (n f)")
  , ("sub"     , "\\m.\\n.n pred m")
  , ("pow"     , "\\b.\\e.e b")
  , ("id"      , "\\x.x")
  , ("true"    , "\\x.\\y.x")
  , ("false"   , "\\x.\\y.y")
  , ("and"     , "\\p.\\q.p q p")
  , ("or"      , "\\p.\\q.p p q")
  , ("not"     , "\\p.p false true")
  , ("if"      , "\\p.\\a.\\b.p a b")
  , ("is_zero" , "\\n.n (\\x.false) true")
  , ("leq"     , "\\m.\\n.is_zero (sub m n)")
  , ("zero"    , "\\f.\\x.x")
  , ("fact"    , "\\k.k (\\p.p (\\a.\\b.\\g.g (\\f.\\x.f (a f x)) (\\f.a (b f))))(\\g.g (\\h.h) (\\h.h)) (\\a.\\b.b)")

  -- SKI combinators

  , ("I"       , "\\x.x")
  , ("K"       , "\\x.\\y.x")
  , ("S"       , "\\x.\\y.\\z.x z (y z)")
  , ("B"       , "\\x.\\y.\\z.x (y z)")
  , ("C"       , "\\x.\\y.\\z.x z y")
  , ("W"       , "\\x.\\y.x y y")
  , ("U"       , "\\x.\\y.y (x x y)")
  , ("Y"       , "\\g.(\\x.g (x x)) (\\x.g (x x))")
  , ("omega"   , "\\x.x x")
  , ("Omega"   , "omega omega")

  , ("pair"    , "\\x.\\y.\\f.f x y")
  , ("first"   , "\\p.p true")
  , ("second"  , "\\p.p false")
  , ("nil"     , "\\x.true")
  , ("null"    , "\\p.p (\\x.\\y.false)")
  ])

where
  f : (String, String) -> Maybe (String, Term)
  f (s, e) = case parse term e of
                  Left  _ => Nothing
                  Right t => Just (s, t)

replaceNats : Term -> Term
replaceNats = rnats [] where
  rnats : List String -> Term -> Term
  rnats bound (Var name) =
    if not (elem name bound) && all isDigit (unpack name)
       then let d = cast name in
                if d > 800 -- Numbers larger than 800 are not Church encoded
                   then Var name
                   else churchEncoded d
       else (Var name)
  rnats bound (App t u) = App (rnats bound t) (rnats bound u)
  rnats bound (Lam v t) = Lam v (rnats (v :: bound) t)

run_ : Nat -> Term -> Eff () [STATE Repl, STDIO]
run_ count term = do
  when (count > 0) (ansiPut "0;32" " \x21d2 ") -- Right arrow
  putStrLn (pretty term)
  when (not (normal term)) continue
where
  continue : Eff () [STATE Repl, STDIO]
  continue = do
    let n = limit !get
    if (count >= n)
       then ansiPut "0;91" ("Terminated! Too many (" ++ show n ++ ") reductions.\n")
       else run_ (succ count) (nor term)

runWithEnv : Term -> Eff () [STATE Repl, STDIO]
runWithEnv term = run_ 0 (term' (dict !get))
where
  term' : Environment -> Term
  term' = foldr (uncurry substitute) (replaceNats term)

partial parseUnsafe : String -> Term
parseUnsafe input =
  case parse term input of
       Right term => term

exit : Eff () [STDIO]
exit = ansiPut "0;37" "Bye!\n"

loop : Eff () [STATE Repl, STDIO, READLINE]
loop = do
  line <- readline "\001\ESC[0;96m\002\x03bb\001\ESC[0m\002 " -- Lambda sign
  case map trim line of
       Just ""  => loop
       Just ":" => loop
       Just str => do
         addHistory str
         if ':' == strHead str
            then do
              case parseCmd (strTail str) of
                   Left err => do
                     putStrLn err
                     loop
                   Right action => do
                     execute action
                     if Quit == action then exit else loop
            else do
              case parse term str of
                   Right t => runWithEnv t
                   otherwise => do
                     ansiPut "0;91" "Not a valid term.\n"
                     putStrLn "Format: <term> := <var> | \\<var>.<term> | (<term> <term>)"
              loop
       Nothing => putChar '\n' *> exit

prog : Eff () [STATE Repl, STDIO, READLINE]
prog = do
  readlineInit
  (ReplState env _) <- get
  addDictEntries (map fst env)
  ansiPut "1;37" "lambdapants"
  putStrLn " \x03bb_\x03bb version 0.0.1"
  putStrLn "Type :h for help"
  loop

main : IO ()
main = Effects.runInit [ReplState stdEnv 150, (), ()] prog
