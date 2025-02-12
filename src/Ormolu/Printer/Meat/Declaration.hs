{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns    #-}

-- | Rendering of declarations.

module Ormolu.Printer.Meat.Declaration
  ( p_hsDecls
  )
where

import GHC
import OccName (occNameFS)
import Ormolu.Printer.Combinators
import Ormolu.Printer.Meat.Common
import Ormolu.Printer.Meat.Declaration.Annotation
import Ormolu.Printer.Meat.Declaration.Class
import Ormolu.Printer.Meat.Declaration.Data
import Ormolu.Printer.Meat.Declaration.Default
import Ormolu.Printer.Meat.Declaration.Foreign
import Ormolu.Printer.Meat.Declaration.Instance
import Ormolu.Printer.Meat.Declaration.RoleAnnotation
import Ormolu.Printer.Meat.Declaration.Rule
import Ormolu.Printer.Meat.Declaration.Signature
import Ormolu.Printer.Meat.Declaration.Splice
import Ormolu.Printer.Meat.Declaration.Type
import Ormolu.Printer.Meat.Declaration.TypeFamily
import Ormolu.Printer.Meat.Declaration.Value
import Ormolu.Printer.Meat.Declaration.Warning
import Ormolu.Printer.Meat.Type
import Ormolu.Utils
import RdrName (rdrNameOcc)

p_hsDecls :: FamilyStyle -> [LHsDecl GhcPs] -> R ()
p_hsDecls style decls = do
  sepSemi (\(x, r) -> located x pDecl >> r) (separated decls)
  where
    pDecl = dontUseBraces . p_hsDecl style

    separated [] = []
    separated [x] = [(x, return ())]
    separated (x:y:xs) =
      if separatedDecls (unLoc x) (unLoc y)
      then (x, breakpoint') : separated (y:xs)
      else (x, return ()) : separated (y:xs)

p_hsDecl :: FamilyStyle -> HsDecl GhcPs -> R ()
p_hsDecl style = \case
  TyClD NoExt x -> p_tyClDecl style x
  ValD NoExt x -> p_valDecl x
  SigD NoExt x -> p_sigDecl x
  InstD NoExt x -> p_instDecl style x
  DerivD NoExt x -> p_derivDecl x
  DefD NoExt x -> p_defaultDecl x
  ForD NoExt x -> p_foreignDecl x
  WarningD NoExt x -> p_warnDecls x
  AnnD NoExt x -> p_annDecl x
  RuleD NoExt x -> p_ruleDecls x
  SpliceD NoExt x -> p_spliceDecl x
  DocD _ _ -> notImplemented "DocD"
  RoleAnnotD NoExt x -> p_roleAnnot x
  XHsDecl _ -> notImplemented "XHsDecl"

p_tyClDecl :: FamilyStyle -> TyClDecl GhcPs -> R ()
p_tyClDecl style = \case
  FamDecl NoExt x -> p_famDecl style x
  SynDecl {..} -> p_synDecl tcdLName tcdFixity tcdTyVars tcdRhs
  DataDecl {..} ->
    p_dataDecl
      Associated
      tcdLName
      (tyVarsToTypes tcdTyVars)
      tcdFixity
      tcdDataDefn
  ClassDecl {..} ->
    p_classDecl
      tcdCtxt
      tcdLName
      tcdTyVars
      tcdFixity
      tcdFDs
      tcdSigs
      tcdMeths
      tcdATs
      tcdATDefs
  XTyClDecl {} -> notImplemented "XTyClDecl"

p_instDecl :: FamilyStyle -> InstDecl GhcPs -> R ()
p_instDecl style = \case
  ClsInstD NoExt x -> p_clsInstDecl x
  TyFamInstD NoExt x -> p_tyFamInstDecl style x
  DataFamInstD NoExt x -> p_dataFamInstDecl style x
  XInstDecl _ -> notImplemented "XInstDecl"

p_derivDecl :: DerivDecl GhcPs -> R ()
p_derivDecl = \case
  d@DerivDecl {..} -> p_standaloneDerivDecl d
  XDerivDecl _ -> notImplemented "XDerivDecl standalone deriving"

-- | Determine if these declarations should be separated by a blank line.

separatedDecls
  :: HsDecl GhcPs
  -> HsDecl GhcPs
  -> Bool
separatedDecls (TypeSignature n) (FunctionBody n') = n /= n'
separatedDecls x (FunctionBody n) | Just n' <- isPragma x = n /= n'
separatedDecls (FunctionBody n) x | Just n' <- isPragma x = n /= n'
separatedDecls x (DataDeclaration n) | Just n' <- isPragma x = n /= n'
separatedDecls (DataDeclaration n) x | Just n' <- isPragma x =
  let f = occNameFS . rdrNameOcc in f n /= f n'
separatedDecls x y | Just n <- isPragma x, Just n' <- isPragma y = n /= n'
separatedDecls x (TypeSignature n') | Just n <- isPragma x = n /= n'
separatedDecls (PatternSignature n) (Pattern n') = n /= n'
separatedDecls _ _ = True

isPragma
  :: HsDecl GhcPs
  -> (Maybe RdrName)
isPragma = \case
  InlinePragma n -> Just n
  SpecializePragma n -> Just n
  SCCPragma n -> Just n
  AnnTypePragma n -> Just n
  AnnValuePragma n -> Just n
  WarningPragma n -> Just n
  _ -> Nothing

pattern TypeSignature
      , FunctionBody
      , InlinePragma
      , SpecializePragma
      , SCCPragma
      , AnnTypePragma
      , AnnValuePragma
      , PatternSignature
      , Pattern
      , WarningPragma
      , DataDeclaration :: RdrName -> HsDecl GhcPs
pattern TypeSignature n <- (sigRdrName -> Just n)
pattern FunctionBody n <- ValD NoExt (FunBind NoExt (L _ n) _ _ _)
pattern InlinePragma n <- SigD NoExt (InlineSig NoExt (L _ n) _)
pattern SpecializePragma n <- SigD NoExt (SpecSig NoExt (L _ n) _ _)
pattern SCCPragma n <- SigD NoExt (SCCFunSig NoExt _ (L _ n) _)
pattern AnnTypePragma n <- AnnD NoExt (HsAnnotation NoExt _ (TypeAnnProvenance (L _ n)) _)
pattern AnnValuePragma n <- AnnD NoExt (HsAnnotation NoExt _ (ValueAnnProvenance (L _ n)) _)
pattern PatternSignature n <- SigD NoExt (PatSynSig NoExt ((L _ n):_) _)
pattern Pattern n <- ValD NoExt (PatSynBind NoExt (PSB _ (L _ n) _ _ _))
pattern WarningPragma n <- WarningD NoExt (Warnings NoExt _ [(L _ (Warning NoExt [(L _ n)] _))])
pattern DataDeclaration n <- TyClD NoExt (DataDecl NoExt (L _ n) _ _ _)

sigRdrName :: HsDecl GhcPs -> Maybe RdrName
sigRdrName (SigD NoExt (TypeSig NoExt ((L _ n):_) _)) = Just n
sigRdrName (SigD NoExt (ClassOpSig NoExt _ ((L _ n):_) _)) = Just n
sigRdrName _ = Nothing
