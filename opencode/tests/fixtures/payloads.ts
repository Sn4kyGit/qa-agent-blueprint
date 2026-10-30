// payloads.ts — golden hook payload shapes for the opencode plugin tests.
//
// These mirror what opencode 1.18.30 actually passes to plugin hooks, captured
// live in spikes S4/S5 (docs/opencode-port-plan.md §5 Phase 0):
//
//   "tool.execute.before": input  = { tool, sessionID, callID }
//                          output = { args: { ...tool-specific } }
//   "tool.execute.after":  input  = { tool, sessionID, callID, args }
//                          output = { title, metadata, output }
//
// The Claude-side fixtures feed JSON to stdin and assert exit codes; here we
// build the equivalent objects and assert throw/no-throw (throw = block).

export const SESSION_ID = "ses_fixture"

export interface BeforeCall {
  input: { tool: string; sessionID: string; callID: string }
  output: { args: Record<string, unknown> }
}

export function bashBefore(command: string): BeforeCall {
  return {
    input: { tool: "bash", sessionID: SESSION_ID, callID: "tool_fixture" },
    output: { args: { command, workdir: "/work" } },
  }
}

export function fileBefore(tool: "write" | "edit" | "read", filePath: string, content?: string, newString?: string): BeforeCall {
  const args: Record<string, unknown> = { filePath }
  if (content !== undefined) args.content = content
  if (newString !== undefined) args.new_string = newString
  return {
    input: { tool, sessionID: SESSION_ID, callID: "tool_fixture" },
    output: { args },
  }
}

/** Malformed/unrecognized call — the guard must fail closed on these. */
export function unknownBefore(rawArgs: Record<string, unknown>): BeforeCall {
  return {
    input: { tool: "", sessionID: SESSION_ID, callID: "tool_fixture" },
    output: { args: rawArgs },
  }
}

export interface AfterCall {
  input: { tool: string; sessionID: string; callID: string; args: Record<string, unknown> }
  output: { title: string; metadata: Record<string, unknown>; output: string }
}

export function toolAfter(tool: string, args: Record<string, unknown> = {}, opts: { error?: boolean } = {}): AfterCall {
  return {
    input: { tool, sessionID: SESSION_ID, callID: "tool_fixture", args },
    output: opts.error
      ? { title: tool, metadata: { error: true }, output: "" }
      : { title: tool, metadata: {}, output: "{}" },
  }
}

/** Minimal fake plugin ctx. client.session.prompt records its calls. */
export function fakeCtx(directory: string) {
  const prompts: unknown[] = []
  return {
    ctx: {
      project: {},
      directory,
      worktree: directory,
      $: {} as never,
      client: {
        session: {
          prompt: async (args: unknown) => {
            prompts.push(args)
            return {}
          },
        },
        app: { log: async () => {} },
      },
    },
    prompts,
  }
}
