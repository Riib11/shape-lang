import { List } from "immutable"

// Term

export type Term = TermUniverse | TermPi | TermLambda | TermLet | TermApplication | TermVariable | TermHole

// Universe

export type TermUniverse = {
  case: "universe",
  universelevel: UniverseLevel;
  format?: {
    indented: boolean
  }
}

export type UniverseLevel = number;

// Pi

export type TermPi = {
  case: "pi",
  label: Label,
  domain: Term,
  codomain: Term,
  format?: {
    indented: boolean,
    annotated: boolean
  }
}

// Lambda

export type TermLambda = {
  case: "lambda",
  label: Label,
  domain: Term,
  body: Term,
  format?: {
    indented: boolean,
    annotated: boolean
  }
}

// Let

export type TermLet = {
  case: "let",
  label: Label,
  domain: Term,
  argument: Term,
  body: Term,
  format?: {
    indented: boolean,
    annotated: boolean
  }
}

// Application

export type TermApplication = {
  case: "application",
  applicant: Term,
  argument: Term,
  format?: {
    indented: boolean
  }
}

// Variable

export type TermVariable = {
  case: "variable",
  debruijnlevel: DeBruijnLevel,
  format?: {
    indented: boolean
  }
}

export type DeBruijnLevel = number;

export type Label = {value: string};

// Hole

export type TermHole = {
  case: "hole",
  holesymbol: HoleSymbol,
  weakening: DeBruijnLevel,
  substitution: Substitution<DeBruijnLevel>
  format?: {
    indented: boolean
  }
}

export type HoleSymbol = Symbol

export type HoleId = number;

export function makeHole(holesymbol: HoleSymbol, weakening: DeBruijnLevel = 0, substitution: Substitution<DeBruijnLevel> = List(), format?: {indented: false}): TermHole {
  return {case: "hole", holesymbol, weakening, substitution, format};
}

export function freshHole(): TermHole {
  const holesymbol: unique symbol = Symbol();
  return makeHole(holesymbol);
}

// Context

// debruijnlevel => [label, type, value?]
export type Context = List<[Label, Term , Term | undefined]>

// Substitution

// A => Term
export type Substitution<A> = List<[A, Term]>;

// Term Index

// A term index specifies a node in a Term AST.
export type TermIx = {} // TODO