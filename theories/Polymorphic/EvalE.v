(** * Interpreter for the Oak language *)

(** This version of the interpreter supports polymorhpic types *)
Require Import String.
Require Import List.
Require Import Polymorphic.Ast MyEnv.

(* TODO: we use definition of monads from Template Coq,
   but (as actually comment in the [monad_utils] says, we
   should use a real monad library) *)
Require Import Template.monad_utils.


Import ListNotations.
Import MonadNotation.

(* Common definitions *)

Inductive res A :=
| Ok : A -> res A
| NotEnoughFuel : res A
| EvalError : string -> res A.


Arguments Ok {_}.
Arguments NotEnoughFuel {_}.
Arguments EvalError {_}.

Instance res_monad : Monad res :=
  { ret := @Ok;
    bind := fun _ _ r f => match r with
                    | Ok v => f v
                    | EvalError msg => EvalError msg
                    | NotEnoughFuel => NotEnoughFuel
                        end }.

Definition res_map {A B} (f : A -> B) (r : res A) : res B :=
  v <- r ;;
  ret (f v).

Definition option_to_res {A : Type} (o : option A) (msg : string) :=
  match o with
  | Some v => Ok v
  | None => EvalError msg
  end.

Definition todo {A} := EvalError (A:=A) "Not implemented".

Module InterpreterEnvList.

  Import Basics.

  Open Scope program_scope.

  (** A type of labels to distinguish closures corresponding to lambdas and fixpoints *)
  Inductive clos_mode : Type :=
    cmLam | cmFix : name -> clos_mode.

  (** Values *)
  Inductive val : Type :=
  | vConstr : inductive -> name -> list val -> val
  | vClos   : env val -> name ->
              clos_mode ->
              type ->(* type of the domain *)
              type ->(* type of the codomain *)
              expr -> val
  | vTyClos : env val -> name -> expr -> val
  | vTy : type -> val.

  Definition ForallEnv {A} (P: A -> Prop) : env A -> Prop := Forall (P ∘ snd).

  (* TODO: Extend this to handle type lambdas and types *)
  Inductive val_ok Σ : val -> Prop :=
  | vokClosLam : forall e nm ρ ty1 ty2,
      ForallEnv (val_ok Σ) ρ ->
      iclosed_n (1 + length ρ) e = true ->
      val_ok Σ (vClos ρ nm cmLam ty1 ty2 e)
  | vokClosFix : forall e nm fixname ρ ty1 ty2,
      ForallEnv (val_ok Σ) ρ ->
      iclosed_n (2 + length ρ) e = true ->
      val_ok Σ (vClos ρ nm (cmFix fixname) ty1 ty2 e)
  | vokContr : forall i nm vs ci,
      Forall (val_ok Σ) vs ->
      resolve_constr Σ i nm = Some ci ->
      val_ok Σ (vConstr i nm vs).

  Definition env_ok Σ (ρ : env val) := ForallEnv (val_ok Σ) ρ.

  (** An induction principle that takes into account nested occurrences of elements of [val] in the list of arguments of [vConstr] and in the environment of [vClos] *)
  Definition val_ind_full
     (P : val -> Prop)
     (Hconstr : forall (i : inductive) (n : name) (l : list val), Forall P l -> P (vConstr i n l))
     (Hclos : forall (ρ : env val) (n : name) (cm : clos_mode) (ty1 ty2 : type) (e0 : expr),
         ForallEnv P ρ -> P (vClos ρ n cm ty1 ty2 e0))
     (Htyclos : forall (ρ : env val) (n : name) (e0 : expr),
         ForallEnv P ρ -> P (vTyClos ρ n e0))
     (Hty : forall (t : type),  P (vTy t)) :
    forall v : val, P v.
    refine (fix val_ind_fix (v : val) := _).
    destruct v.
    + apply Hconstr.
      induction l. constructor. constructor. apply val_ind_fix. apply IHl.
    + apply Hclos.
      induction e.
      * constructor.
      * constructor. apply val_ind_fix. apply IHe.
    + apply Htyclos.
      induction e.
      * constructor.
      * constructor. apply val_ind_fix. apply IHe.
    + apply Hty.
  Defined.

  (** For some reason, this is not a part of the standard lib *)
  Lemma Forall_app {A} (l1 l2 : list A) P :
    Forall P (l1 ++ l2) <-> Forall P l1 /\ Forall P l2.
  Proof.
    split.
    - intros H. induction l1.
      + simpl in *. easy.
      + simpl in *. inversion H. subst.
        split.
        * constructor. assumption.
          destruct (IHl1 H3). assumption.
        * destruct (IHl1 H3). assumption.
    - intros H. induction l1.
      + simpl in *. easy.
      + simpl in *. destruct H as [H1 H2].
        constructor;inversion H1;auto.
  Qed.

  Lemma Forall_rev {A} {l : list A} P : Forall P l -> Forall P (rev l).
  Proof.
    intros H.
    induction l.
    + constructor.
    + simpl. apply Forall_app.
      inversion H;auto.
  Qed.

  Definition ind_name (v : val) :=
    match v with
    | vConstr ind_name _ _ => Some ind_name
    | _ => None
    end.

  Open Scope string.

  (** Very simple implementation of pattern-matching. Note that we do not match on parameters of constructors coming from parameterised inductives *)
  Definition match_pat {A} (cn : name) (nparam : nat) (arity :list type)
             (constr_args : list A) (bs : list (pat * expr)) :=
    pe <- option_to_res (find (fun x => (fst x).(pName) =? cn) bs) (cn ++ ": not found");;
    let '(p,e) := pe in
    let ctr_len := length constr_args in
    let pt_len := nparam + length p.(pVars) in
    let arity_len := nparam + (length arity) in
    if (Nat.eqb ctr_len pt_len) then
      if (Nat.eqb ctr_len arity_len) then
        (* NOTE: first [nparam] elements in the [constr_args] are types, so we don't match them *)
        let args := skipn nparam constr_args in
        let assignments := combine p.(pVars) args in
        Ok (assignments,e)
      else EvalError (cn ++ ": constructor arity does not match")
    else EvalError (cn ++ ": pattern arity does not match (constructor: "
                       ++ utils.string_of_nat ctr_len ++ ",
                    pattern: "  ++ utils.string_of_nat pt_len ++ ")").

  Fixpoint inductive_name (ty : type) : option name :=
    match ty with
    | tyInd nm => Some nm
    | tyApp ty1 ty2 => inductive_name ty1
    | _ => None
    end.

  (** Some machinery to substitute type during the evaluation. Although we don't care about the type during evaluation, we need the types later. *)
  Fixpoint eval_type_i (k : nat) (ρ : env val) (ty : type) : option type :=
    match ty with
    | tyInd x => Some ty
    | tyForall x ty => ty' <- (eval_type_i (1+k) ρ ty);;
                       ret (tyForall x ty')
    | tyApp ty1 ty2 =>
      ty2' <- eval_type_i k ρ ty2;;
      ty1' <- eval_type_i k ρ ty1;;
      ret (tyApp ty1' ty2')
    | tyVar nm => None
    | tyRel i => if Nat.leb k i then
                  match (lookup_i ρ i) with
                  | Some (vTy ty) => Some ty
                  | _ => None
                  end
                else Some ty
    | tyArr ty1 ty2 =>
      (* NOTE: we pass [1+k] for the ty2 evaluation
         due to the [indexify] function (see comments there) *)
      ty2' <- eval_type_i (1+k) ρ ty2;;
      ty1' <- eval_type_i k ρ ty1;;
      Some (tyArr ty1' ty2')
    end.

  (** The same as [eval_type_i] but for named variables *)
  Fixpoint eval_type_n (ρ : env val) (ty : type) : option type :=
    match ty with
    | tyInd x => Some ty
    | tyForall x ty => ty' <- eval_type_n (remove_by_key x ρ) ty;;
                       ret (tyForall x ty')
    | tyApp ty1 ty2 =>
      ty2' <- eval_type_n ρ ty2;;
      ty1' <- eval_type_n ρ ty1;;
      ret (tyApp ty1' ty2')
    | tyVar nm => match lookup ρ nm with
                    | Some (vTy ty) => Some ty
                    | _ => None
                    end
    | tyRel i => None
    | tyArr ty1 ty2 =>
      ty2' <- eval_type_n ρ ty2;;
      ty1' <- eval_type_n ρ ty1;;
      Some (tyArr ty1' ty2')
    end.


  Fixpoint print_type (ty : type) : string :=
    match ty with
    | tyInd x => x
    | tyForall x x0 => "forall " ++ x ++ "," ++ print_type x0
    | tyApp x x0 => "(" ++ print_type x ++ " " ++ print_type x0 ++ ")"
    | tyVar x => x
    | tyRel x => "^" ++ utils.string_of_nat x
    | tyArr x x0 => print_type x ++ "->" ++ print_type x0
    end.


  (** The interpreter works for both named and nameless representation of Oak expressions, depending on a parameter [named]. Due to the potential non-termination of Oak programs, we define our interpreter using a fuel idiom: by structural recursion on an additional argument (a natural number). We keep types in during evaluation, because for the soundness theorem we would have to translate values back to expression and then further to MetaCoq terms. This requires us to keep all types in place. In addition to this interpreter, we plan to implement another one which computes on terms after erasure of typing information. *)

  Fixpoint expr_eval_general (fuel : nat) (named : bool) (Σ : global_env)
           (ρ : env val) (e : expr) : res val :=
    match fuel with
    | O => NotEnoughFuel
    | S n =>
      match e with
      | eRel i => if named then EvalError "Indices as variables are not supported"
                  else option_to_res (lookup_i ρ i) ("var not found")
      | eVar nm => if named then
                    option_to_res (ρ # (nm)) (nm ++ " - var not found")
                  else EvalError (nm ++ " variable found, but named variables are not supported")
      | eLambda nm ty b =>
      (* NOTE: we pass the same type as the codomain type here
        (because it's not needed for lambda).
        Maybe separate costructors for lambda/fixpoint closures would be better? *)
        Ok (vClos ρ nm cmLam ty ty b)
      | eLetIn nm e1 ty e2 =>
        v <- expr_eval_general n named Σ ρ e1 ;;
        expr_eval_general n named Σ (ρ # [nm ~> v]) e2
      | eApp e1 e2 =>
        v2 <- expr_eval_general n named Σ ρ e2;;
        v1 <- expr_eval_general n named Σ ρ e1;;
        match v1,v2 with
        | vClos ρ' nm cmLam _ _ b, v =>
          res <- (expr_eval_general n named Σ (ρ' # [nm ~> v]) b);;
          ret res
        | vClos ρ' nm (cmFix fixname) ty1 ty2 b, v =>
          let v_fix := (vClos ρ' nm (cmFix fixname) ty1 ty2 b) in
          res <- expr_eval_general n named Σ (ρ' # [fixname ~> v_fix] # [nm ~> v]) b;;
          ret res
        | vTyClos ρ' nm b, v =>
            res <- (expr_eval_general n named Σ (ρ' # [nm ~> v]) b);;
            ret res
        | vConstr ind n vs, v => Ok (vConstr ind n (List.app vs [v]))
        | _, _ => EvalError "eApp : not a constructor or closure"
        end
      | eConstr ind ctor =>
        match (resolve_constr Σ ind ctor) with
        | Some _ => Ok (vConstr ind ctor [])
        | _ => EvalError "No constructor or inductive found"
        end
      | eConst nm => todo
      | eCase (ind,i) ty e bs =>
        match (expr_eval_general n named Σ ρ e) with
        | Ok (vConstr ind' c vs) =>
          match resolve_constr Σ ind' c with
          | Some (_,ci) =>
            (* TODO : move cheking inductive names before
               resolving the constructor *)
            ind_nm <- option_to_res (inductive_name ind) "not inductive";;
            if (string_dec ind_nm ind') then
              pm_res <- match_pat c i ci vs bs;;
              let '(var_assign, v) := pm_res in
                expr_eval_general n named Σ (List.app (rev var_assign) ρ) v
            else EvalError ("Expecting inductive " ++ ind_nm ++
                            " but found " ++ ind')
            | None => EvalError "No constructor or inductive found in the global envirionment"
          end
        | Ok (vTy ty) => EvalError ("Discriminee cannot be a type : " ++ print_type ty)
        | Ok _ => EvalError "Discriminee should evaluate to a constructor"
        | v => v
        end
      | eFix fixname vn ty1 ty2 b as e =>
        Ok (vClos ρ vn (cmFix fixname) ty1 ty2 b)
      | eTyLam nm e => Ok (vTyClos ρ nm e)
      | eTy ty =>
        let error := "Error while evaluating type: " ++ print_type ty in
        let res := if named then
                     option_to_res (eval_type_n ρ ty) error
                     else option_to_res (eval_type_i 0 ρ ty) error in
        ty' <- res;; ret (vTy ty')
      end
    end.

  Definition expr_eval_n n := expr_eval_general n true.
  Definition expr_eval_i n := expr_eval_general n false.

Module Examples.
  Import BaseTypes.
  Import StdLib.

  Open Scope string.

  Definition prog1 :=
    [|
     (\x : Bool =>
           case x : Bool return Bool of
           | True -> False
           | False -> True) True
     |].

  Example eval_prog1_named :
    InterpreterEnvList.expr_eval_n 3 Σ [] prog1 = Ok (InterpreterEnvList.vConstr "Coq.Init.Datatypes.bool" "false" []).
  Proof. simpl. reflexivity. Qed.

  Example eval_prog1_indexed :
    InterpreterEnvList.expr_eval_i 3 Σ [] (indexify [] prog1) = Ok (InterpreterEnvList.vConstr "Coq.Init.Datatypes.bool" "false" []).
  Proof. simpl. reflexivity. Qed.

  End Examples.
End InterpreterEnvList.