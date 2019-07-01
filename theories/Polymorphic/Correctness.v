(** * The statement of a soundness theorem *)
(** We stated a soundness theorem for the translation from polymorphic Oak to MetaCoq terms. We plan to adapt and extend the soundness theorem for a monomorphic fragment of Oak. *)
Require Template.WcbvEval.
Require Import Template.LiftSubst.
Require Import Template.All.

Require Import String List Basics.

Require Import CustomTactics MyEnv.
Require Import Polymorphic.Ast Polymorphic.EvalE Polymorphic.EnvSubst.

Import InterpreterEnvList.
Notation "'eval' ( n , Σ , ρ , e )"  := (expr_eval_i n Σ ρ e) (at level 100).

Import ListNotations.
Open Scope list_scope.

Import Lia.

Notation "Σ ;;; Γ |- t1 ⇓ t2 " := (WcbvEval.eval Σ Γ t1 t2) (at level 50).
Notation "T⟦ e ⟧ Σ " := (expr_to_term Σ e) (at level 49).

Notation exprs := (map (fun x => (fst x, from_val_i (snd x)))).

Conjecture expr_to_term_sound : forall (n : nat) (ρ : env val) Σ1 Σ2 (Γ:=[]) (e1 e2 : expr) (t : term) (v : val),
  env_ok Σ1 ρ ->
  Σ2 ;;; Γ |- T⟦e2⟧Σ1 ⇓ t ->
  eval(n, Σ1, ρ, e1) = Ok v ->
  e1.[exprs ρ] = e2 ->
  iclosed_n 0 e2 = true ->
  t = T⟦from_val_i v⟧Σ1.