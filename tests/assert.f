// The smallest possible test harness: check() counts, finish() reports
// and exits non-zero on any failure so a shell runner can chain files.
int checksPassed = 0
int checksFailed = 0

void func check(cond:bool, label:text) {
    if cond {
        checksPassed++
    } else {
        checksFailed++
        log(`FAIL: ${label}`)
    }
}

void func checkEq(actual:text, expected:text, label:text) {
    if actual == expected {
        checksPassed++
    } else {
        checksFailed++
        log(`FAIL: ${label}`)
        log(`  expected: ${expected}`)
        log(`  actual:   ${actual}`)
    }
}

void func checkEqInt(actual:int, expected:int, label:text) {
    if actual == expected {
        checksPassed++
    } else {
        checksFailed++
        log(`FAIL: ${label}: expected ${expected}, got ${actual}`)
    }
}

// Within `slack` either way. A painted geometry lands on an integer
// pixel and the number it came from did not, so a check against the
// browser's rectangle is a check to within a pixel.
void func checkNear(actual:int, expected:int, slack:int, label:text) {
    int d = actual - expected
    if d < 0 { d = 0 - d }
    if d <= slack {
        checksPassed++
    } else {
        checksFailed++
        log(`FAIL: ${label}: expected ${expected} +/- ${slack}, got ${actual}`)
    }
}

// Exits explicitly rather than falling off the end: the preload
// workers are live threads, and a live thread keeps the program
// running (specification 12.1). See FINDINGS.md, "a declared thread
// makes the program non-terminating".
void func finish(suite:text) {
    log(`${suite}: ${checksPassed} passed, ${checksFailed} failed`)
    close(checksFailed > 0 ? 1 : 0)
}
