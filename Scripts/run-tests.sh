#!/bin/bash
# The test suite. There is no XCTest target: each harness compiles the shipped sources it guards,
# so a harness that stops compiling means a decision leaked out of a pure layer. See docs/testing.md.
#
# Never join a compile and its run with `&&`: `set -e` ignores a failure in a non-final AND-OR list
# member, which would report success over a harness that never compiled.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/noto-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall the suite.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((NOTO_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$NOTO_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${NOTO_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

QUEUE="$BIN/queue"
: > "$QUEUE"
rm -f "$BIN"/*.failed "$BIN"/*.running

failed=()
ran=0
only="${1:-}"

# `--index` merges each harness's compile command into .compile instead of running anything.
# xcodebuild never compiles the harnesses, so without this nothing in Tests/ resolves in an editor.
# The source lists below are the only copy, which is why this lives here rather than in its own script.
emit_db=0
DB="${TMPDIR:-/tmp}/noto-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

# run [slow] [-O] [index] <name> <source...> — queue the harness. `slow` dispatches it in the first
# wave; `index` claims editor flags for a harness that is compiled by hand rather than by the suite.
run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths throughout: sourcekit-lsp resolves the command itself and does not apply
    # `directory` to relative arguments, so a relative path there silently yields no index.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Claim every file under `Tests/`: the harness and any helper compiled beside it. A shipped
        # source stays unclaimed, because it would get this short command instead of the app's full
        # one and `.compile` is last-wins — but the app never compiles anything in `Tests/`.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

run notes-test             Noto/Platform/Signposts.swift \
                           Noto/Features/Notes/Model/*.swift \
                           Noto/Features/Notes/Service/*.swift
run notes-editor-test      Noto/Platform/Signposts.swift \
                           Noto/Platform/Appearance.swift \
                           Noto/DesignSystem/Theme.swift \
                           Noto/DesignSystem/InterfaceMetrics.swift \
                           Noto/Platform/NotificationToken.swift \
                           Noto/Features/Notes/Model/NoteDocument.swift \
                           Noto/Features/Notes/Model/NoteMarkdown.swift \
                           Noto/Features/Notes/Model/NoteMarkdownParser.swift \
                           Noto/Features/Notes/Model/NoteInlineScanner.swift \
                           Noto/Features/Notes/Model/NoteEditPlan.swift \
                           Noto/Features/Notes/Model/NoteEditAction.swift \
                           Noto/Features/Notes/Model/NoteFormatting.swift \
                           Noto/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Noto/Features/Notes/Model/NoteRevealPolicy.swift \
                           Noto/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Noto/Features/Notes/UI/NoteBlockDecoration.swift \
                           Noto/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Noto/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Noto/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Noto/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Noto/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Noto/Features/Notes/UI/NoteTextViewEditing.swift \
                           Noto/Features/Notes/UI/NoteTextView.swift \
                           Noto/Features/Notes/UI/NoteEditorView.swift
run -O index notes-editor-performance \
                           Noto/Platform/Signposts.swift \
                           Noto/Platform/Appearance.swift \
                           Noto/DesignSystem/Theme.swift \
                           Noto/DesignSystem/InterfaceMetrics.swift \
                           Noto/Platform/NotificationToken.swift \
                           Noto/Features/Notes/Model/NoteDocument.swift \
                           Noto/Features/Notes/Model/NoteMarkdown.swift \
                           Noto/Features/Notes/Model/NoteMarkdownParser.swift \
                           Noto/Features/Notes/Model/NoteInlineScanner.swift \
                           Noto/Features/Notes/Model/NoteEditPlan.swift \
                           Noto/Features/Notes/Model/NoteEditAction.swift \
                           Noto/Features/Notes/Model/NoteFormatting.swift \
                           Noto/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Noto/Features/Notes/Model/NoteRevealPolicy.swift \
                           Noto/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Noto/Features/Notes/UI/NoteBlockDecoration.swift \
                           Noto/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Noto/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Noto/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Noto/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Noto/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Noto/Features/Notes/UI/NoteTextViewEditing.swift \
                           Noto/Features/Notes/UI/NoteTextView.swift \
                           Noto/Features/Notes/UI/NoteEditorView.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${NOTO_TEST_JOBS:-4}"
export NOTO_TEST_TIMEOUT="${NOTO_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in "dispatch "*) return "${line#dispatch }";; esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! { sort -s -k1,1n "$QUEUE" | cut -d' ' -f2- | xargs -P "$JOBS" -L1 "$SELF" --exec; echo "dispatch $?"; } | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
