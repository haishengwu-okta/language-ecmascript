module WebBits.JavaScript.CoreTransform 
  ( simplify
  ) where

import qualified Data.Set as S
import qualified Data.Maybe as Y
import qualified Data.List as L
import Control.Monad.State

import WebBits.Common
import Data.Generics

import WebBits.JavaScript.Syntax
import qualified WebBits.JavaScript.Core as Core
import WebBits.JavaScript.Env

noPos = initialPos "WebBits.JavaScript.CoreTransform"

removeFuncStmt :: Statement SourcePos -> Statement SourcePos
removeFuncStmt (FunctionStmt p name args body) = VarDeclStmt p [decl] where
  decl = VarDecl p name (Just funcExpr)
  funcExpr = FuncExpr p args body
removeFuncStmt stmt = stmt

-- |For each FuncExpr, creates a VarDecl at the top that names all locally
-- defined variables.
pseudoLetBindings :: Expression SourcePos -> Expression SourcePos
pseudoLetBindings (FuncExpr p args body) = FuncExpr p args body' where
  body' = BlockStmt p [binds,body]
  binds = VarDeclStmt p (map (\name -> VarDecl p (Id p name) Nothing) locals)
  locals = S.toList (localVars [body])
pseudoLetBindings expr = expr

-- |Once all variables are declared at the head of each function, we can
-- remove variable declarations from within the function body.
removeInnerVarDecls :: Expression SourcePos -> Expression SourcePos
removeInnerVarDecls (FuncExpr p args (BlockStmt p' [binds,body])) = expr' where
  expr' = FuncExpr p args (BlockStmt p' [binds,body'])
  body' = everywhereBut (not.excludeFunctions) 
            (mkT removeVarDecl `extT` unVarForInit `extT` unVarForInInit)
            body
 

  unVarForInit :: ForInit SourcePos -> ForInit SourcePos
  unVarForInit (VarInit decls) = case Y.mapMaybe unDecl decls of
    [] -> NoInit
    exprs -> ExprInit (ListExpr noPos exprs)
  unVarForInit init            = init
  
  unVarForInInit :: ForInInit SourcePos -> ForInInit SourcePos
  unVarForInInit (ForInVar id) = ForInNoVar id
  unVarForInInit init          = init

 
  removeVarDecl :: Statement SourcePos -> Statement SourcePos
  removeVarDecl (VarDeclStmt p decls) = case Y.mapMaybe unDecl decls of
    [] -> EmptyStmt p
    exprs -> ExprStmt p (ListExpr p exprs)
  removeVarDecl stmt                  = stmt

  unDecl :: VarDecl SourcePos -> Maybe (Expression SourcePos)
  unDecl (VarDecl p id Nothing) = Nothing
  unDecl (VarDecl p id (Just e)) = Just $ AssignExpr p OpAssign (VarRef p id) e 
removeInnerVarDecls expr = expr


removeForStmt :: Statement SourcePos -> Statement SourcePos
removeForStmt (ForStmt p init maybeTest maybeIncr body) = stmts where
  stmts = BlockStmt p [prelude,WhileStmt p whileTest whileBody]
  prelude = case init of
    NoInit -> EmptyStmt p
    ExprInit e -> ExprStmt p e
    -- following shouldn't happen, but allows this function to be used alone
    VarInit decls -> VarDeclStmt p decls
  whileTest = case maybeTest of
    Nothing -> BoolLit p True
    Just e -> e
  whileBody = BlockStmt p [body,whileIncr]
  whileIncr = case maybeIncr of
    Nothing -> EmptyStmt p
    Just e -> ExprStmt p e
removeForStmt stmt = stmt 

removeDoWhileStmt :: Statement SourcePos -> Statement SourcePos
removeDoWhileStmt (DoWhileStmt p body test) = stmts where
  stmts = BlockStmt p [body,WhileStmt p test body]
removeDoWhileStmt stmt = stmt

removeIfSingleStmt :: Statement SourcePos -> Statement SourcePos
removeIfSingleStmt (IfSingleStmt p test body) =
  IfStmt p test body (EmptyStmt p)
removeIfSingleStmt stmt = stmt

simplifyStmts = removeForStmt.removeDoWhileStmt.removeIfSingleStmt

-- |Applied bottom up, so it can assume its children are simplified
simplifyBlocks :: Statement SourcePos -> Statement SourcePos
simplifyBlocks (BlockStmt p stmts) = result where
  result = case stmts' of
    [] -> EmptyStmt p
    [stmt] -> stmt
    _ -> BlockStmt p stmts'
  stmts' = concatMap simpl stmts
  simpl (EmptyStmt{}) = []
  simpl (BlockStmt p stmts) = stmts
  simpl stmt = [stmt]
simplifyBlocks stmt = stmt 
 

simplify :: [Statement SourcePos] -> [Statement SourcePos]
simplify script =  resimplified where
  resimplified = everywhere (mkT simplifyBlocks)
    $ everywhere (mkT removeInnerVarDecls)
    $ everywhere (mkT pseudoLetBindings) purified
  purified = evalState (mapM purifyExprs simplified) 0
  simplified = everywhere (mkT simplifyStmts)
    $ everywhere (mkT removeInnerVarDecls)
    $ everywhere (mkT pseudoLetBindings)
    $ everywhere (mkT removeFuncStmt) script



assign :: Expression SourcePos -> Expression SourcePos -> Statement SourcePos
assign e1 e2 = ExprStmt noPos (AssignExpr noPos OpAssign e1 e2)

newLocalVar :: Expression SourcePos 
            -> State Int (Statement SourcePos,Expression SourcePos)
newLocalVar expr = do
  n <- get
  put (n+1)
  let id = Id noPos ("__webbits" ++ show n)
  return (VarDeclStmt noPos [VarDecl noPos id (Just expr)],VarRef noPos id)

-- |Lifts functions calls out of expressions into a sequence of
-- statements.
sepEffects :: Expression SourcePos 
           -> State Int ([Statement SourcePos],Expression SourcePos)
sepEffects expr = case expr of
  StringLit{} -> return ([],expr)
  RegexpLit{} -> return ([],expr)
  NumLit{} -> return ([],expr)
  BoolLit{} -> return ([],expr)
  NullLit{} -> return ([],expr)
  ArrayLit p es -> do
    r <- mapM sepEffects es
    return (concatMap fst r,ArrayLit p $ map snd r)
  VarRef{} -> return ([],expr)
  CondExpr p e1 e2 e3 -> do 
    (e1Stmts,e1Expr) <- sepEffects e1
    (e2Stmts,e2Expr) <- sepEffects e2
    (e3Stmts,e3Expr) <- sepEffects e3
    case (e2Stmts,e3Stmts) of
      ([],[]) -> return (e1Stmts,CondExpr p e1Expr e2Expr e3Expr)
      otherwise -> do
        (decl,ref) <- newLocalVar e1Expr
        let e2Stmts' = BlockStmt p [BlockStmt p e2Stmts,assign ref e2Expr]
        let e3Stmts' = BlockStmt p [BlockStmt p e3Stmts,assign ref e3Expr]
        return ([BlockStmt p e1Stmts,IfStmt p ref e2Stmts' e3Stmts'],ref)
  ParenExpr p e -> sepEffects e
  CallExpr p fn args -> do
    (fnStmts,fnExpr) <- sepEffects fn
    r <- mapM sepEffects args
    let (argsStmts,argExprs) = (concatMap fst r,map snd r)
    (decl,ref) <- newLocalVar $ CallExpr p fnExpr argExprs
    return (fnStmts ++ argsStmts ++ [decl],ref)
  FuncExpr p args body -> do
    expr <- liftM (FuncExpr p args) (purifyExprs body)
    return ([],expr)
  AssignExpr p op lhs rhs -> do
    (rhsStmts,rhs') <- sepEffects rhs
    (lhsStmts,lhs') <- sepEffects lhs
    case (rhsStmts,lhsStmts) of
      ([],[]) -> return ([ExprStmt p expr],lhs)
      otherwise -> do
        let stmts = lhsStmts ++ rhsStmts ++ 
                      [ExprStmt p (AssignExpr p op lhs' rhs')]
        return (stmts,lhs')
  ListExpr p es -> do
    r <- mapM sepEffects es
    return (concatMap fst r,snd $ L.last r) -- discard earlier expressions
  InfixExpr p op lhs rhs
    | op == OpLAnd -> do
      (lhsStmts,lhs') <- sepEffects lhs
      (rhsStmts,rhs') <- sepEffects rhs
      case rhsStmts of
        [] -> return (lhsStmts,InfixExpr p op lhs' rhs')
        otherwise -> do
          (decl,ref) <- newLocalVar lhs'
          let rhsStmts' = rhsStmts ++ [assign ref rhs']
          return ([BlockStmt p lhsStmts,
                   IfStmt p ref (BlockStmt p rhsStmts') (EmptyStmt p)],
                  ref)

    | otherwise -> do
      (lhsStmts,lhs') <- sepEffects lhs
      (rhsStmts,rhs') <- sepEffects rhs
      return (lhsStmts ++ rhsStmts, InfixExpr p op lhs' rhs')
  PostfixExpr p op e -> do
    (eStmts,e') <- sepEffects e
    (declStmt,id) <- newLocalVar e'
    let modifyExpr = AssignExpr p OpAssign e' $ case op of
          PostfixInc -> InfixExpr p OpAdd e' (NumLit p 1)
          PostfixDec -> InfixExpr p OpSub e' (NumLit p 1) 
    return (eStmts ++ [declStmt,ExprStmt p modifyExpr],id)
  PrefixExpr p op e -> do
    (eStmts,e') <- sepEffects e
    case op of
      PrefixInc ->
        return (eStmts ++ [assign e' (InfixExpr p OpAdd e' (NumLit p 1))],e')
      PrefixDec ->
        return (eStmts ++ [assign e' (InfixExpr p OpSub e' (NumLit p 1))],e')
      PrefixDelete ->
        return (eStmts ++ [ExprStmt p (PrefixExpr p PrefixDelete e')],
                BoolLit p True)
      otherwise -> 
        return (eStmts,PrefixExpr p op e')
  ObjectLit p pes -> do
    let (props,exprs) = unzip pes
    r <- mapM sepEffects exprs
    return (concatMap fst r, ObjectLit p $ zip props (map snd r))
  ThisRef p -> return ([],expr)
  DotRef p e id -> do
    (eStmts,e') <- sepEffects e
    return (eStmts,DotRef p e' id)
  BracketRef p e1 e2 -> do
    (e1Stmts,e1') <- sepEffects e1
    (e2Stmts,e2') <- sepEffects e2
    return (e1Stmts ++ e2Stmts,BracketRef p e1' e2')
  NewExpr p constr args -> do
    (constrStmts,constr') <- sepEffects constr
    r <- mapM sepEffects args
    let argsStmts = concatMap fst r
    let args' = map snd r
    return (constrStmts ++ argsStmts,NewExpr p constr' args')

purifyExprs :: Statement SourcePos -> State Int (Statement SourcePos)
purifyExprs stmt = case stmt of
  BlockStmt p stmts -> liftM (BlockStmt p) (mapM purifyExprs stmts)
  EmptyStmt{} -> return stmt
  ExprStmt p e -> do
    (stmts,_) <- sepEffects e -- discard the pure expression
    return $ if null stmts then (EmptyStmt p) else (BlockStmt p stmts)
  IfStmt p e s1 s2 -> do
    (ess,e') <- sepEffects e
    s1' <- purifyExprs s1
    s2' <- purifyExprs s2
    return (BlockStmt p [BlockStmt p ess,IfStmt p e' s1' s2'])
  SwitchStmt p e cases -> fail "cannot handle switch yet"
  WhileStmt p e s -> do
    (ess,e') <- sepEffects e
    s' <- purifyExprs s
    return (BlockStmt p [BlockStmt p ess,WhileStmt p e' s'])
  BreakStmt{} -> return stmt
  ContinueStmt{} -> return stmt
  ForInStmt p init expr body -> do
    (exprStmts,expr') <- sepEffects expr
    body' <- purifyExprs body
    return (BlockStmt p [BlockStmt p exprStmts,ForInStmt p init expr' body']) 
  TryStmt p body catches finally -> fail "cannot handle try yet"
  ThrowStmt p e -> do
    (es,e') <- sepEffects e
    return (BlockStmt p [BlockStmt p es,ThrowStmt p e'])
  ReturnStmt p Nothing -> return stmt
  ReturnStmt p (Just e) -> do
    (es,e') <- sepEffects e
    return (BlockStmt p [BlockStmt p es,ReturnStmt p (Just e')])
  WithStmt{} -> fail "cannot handle With yet"
  VarDeclStmt p decls -> do
    r <- mapM purifyDecl decls
    return (BlockStmt p [BlockStmt p (concatMap fst r), 
                         VarDeclStmt p (map snd r)])
  otherwise -> fail $ "purifyExpr received " ++ show stmt

purifyDecl :: VarDecl SourcePos 
           -> State Int ([Statement SourcePos],VarDecl SourcePos)
purifyDecl decl@(VarDecl p id rhs) = case rhs of
  Nothing -> return ([],decl)
  Just expr -> do
    (ss,e) <- sepEffects expr
    return (ss,VarDecl p id (Just e))