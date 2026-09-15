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

void func finish(suite:text) {
    log(`${suite}: ${checksPassed} passed, ${checksFailed} failed`)
    if checksFailed > 0 { close(1) }
}
