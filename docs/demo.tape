Output demo.gif

Set Shell zsh
Set FontSize 18
Set Width 1200
Set Height 750
Set TypingSpeed 35ms
Set Theme Dracula

Sleep 800ms
Type "QA Agent Blueprint"
Enter
Sleep 400ms
Type "AI QA Manager for Claude Code & opencode"
Enter
Sleep 400ms
Type "JIRA ticket in -> tested ticket out, mandatory evidence, learning loop"
Enter
Sleep 1500ms

Type clear
Enter
Sleep 500ms

Type claude
Enter
Sleep 2000ms

Type "  QA Agent Blueprint v0.20.0"
Enter
Sleep 300ms
Type "  33 skills - 9 agents - 4 hooks - 2 MCP servers"
Enter
Sleep 800ms

Type "/test-ticket SHOP-123"
Enter
Sleep 1500ms

Type "  Reading ticket SHOP-123..."
Enter
Sleep 600ms
Type "  Summary: Checkout button not working on mobile"
Enter
Sleep 400ms
Type "  AC1: Button is clickable on all viewports"
Enter
Type "  AC2: Clicking opens the checkout flow"
Enter
Sleep 800ms

Type "  Routing: project=SHOP, product=STOREFRONT"
Enter
Sleep 600ms

Type "  Preflight: stage OK, JIRA OK, VPN OK, secrets 4/4"
Enter
Sleep 800ms

Type "  Testing... (Playwright MCP on stage)"
Enter
Sleep 1200ms
Type "  TC-CHK-001: Button visible 375px ......... PASS"
Enter
Type "  TC-CHK-002: Button visible 768px ......... PASS"
Enter
Type "  TC-CHK-003: Click opens checkout ......... FAIL"
Enter
Type "  TC-CHK-004: aria-label correct ........... PASS"
Enter
Sleep 1000ms

Type "  Analyzing failure: product-defect (high confidence)"
Enter
Sleep 800ms

Type "  Evidence written:"
Enter
Sleep 300ms
Type "    evidence/SHOP/SHOP-123/20261102-143022/"
Enter
Type "    + execution_summary.json, screenshots, failure-analysis.md"
Enter
Sleep 800ms

Type "  Bug filed: SHOP-456 (P1, product-defect)"
Enter
Sleep 600ms

Type clear
Enter
Sleep 300ms

Type "  TEST COMPLETE - SHOP-123"
Enter
Sleep 400ms
Type ""
Enter
Type "  Verdict:    FAIL (1 of 4 tests)"
Enter
Type "  Bug:        SHOP-456 (P1)"
Enter
Type "  Evidence:   8 artifacts"
Enter
Type "  Learning:   1 new capture"
Enter
Type "  JIRA:       Comment posted (shadow mode)"
Enter
Sleep 1000ms

Type ""
Enter
Type "  No evidence, no verdict. Every run produces proof."
Enter
Sleep 2000ms

Type clear
Enter
Sleep 300ms
Type "  github.com/Sn4kyGit/qa-agent-blueprint"
Enter
Sleep 300ms
Type "  Star it if you find it useful!"
Enter
Sleep 3000ms
