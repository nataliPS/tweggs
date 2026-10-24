// Domain errors. `code` matches Firebase HttpsError codes so the adapter maps 1:1.

export type ErrorCode =
  | "unauthenticated"
  | "invalid-argument"
  | "not-found"
  | "permission-denied"
  | "failed-precondition"
  | "resource-exhausted"
  | "already-exists"
  | "internal";

export class DomainError extends Error {
  readonly code: ErrorCode;
  /** Stable machine-readable reason for the client (e.g. "preview-cap"). */
  readonly reason: string;
  constructor(code: ErrorCode, reason: string, message?: string) {
    super(message ?? reason);
    this.name = "DomainError";
    this.code = code;
    this.reason = reason;
  }
}

export const fail = (code: ErrorCode, reason: string, message?: string): never => {
  throw new DomainError(code, reason, message);
};
