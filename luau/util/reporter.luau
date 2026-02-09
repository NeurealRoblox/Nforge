--!strict
-- Reporter: colored step-by-step console output.

local stdio = require("@lune/stdio")

local Reporter = {}

function Reporter.checkOk(label: string)
	print(
		`  {stdio.style("dim")}[CHECK]{stdio.style("reset")} {label} ... {stdio.color("green")}OK{stdio.color("reset")}`
	)
end

function Reporter.checkFail(label: string, message: string)
	print(
		`  {stdio.style("dim")}[CHECK]{stdio.style("reset")} {label} ... {stdio.color("red")}{stdio.style("bold")}FAILED{stdio.style("reset")}{stdio.color("reset")}`
	)
	print(`          {message}`)
end

function Reporter.stepOk(label: string)
	print(`    {stdio.color("green")}[OK]{stdio.color("reset")} {label}`)
end

function Reporter.stepFail(label: string, message: string)
	print(
		`    {stdio.color("red")}{stdio.style("bold")}[FAIL]{stdio.style("reset")}{stdio.color("reset")} {label}`
	)
	print(`          {message}`)
end

function Reporter.progress(index: number, total: number, label: string)
	stdio.write(
		`  {stdio.style("dim")}[{index}/{total}]{stdio.style("reset")} {label}... `
	)
end

function Reporter.progressOk(elapsed: string)
	print(`{stdio.color("green")}OK{stdio.color("reset")} ({elapsed})`)
end

function Reporter.progressFail(message: string)
	print(`{stdio.color("red")}{stdio.style("bold")}FAILED{stdio.style("reset")}{stdio.color("reset")}`)
	print(`        {message}`)
end

function Reporter.error(message: string)
	print(
		`\n  {stdio.color("red")}{stdio.style("bold")}ERROR:{stdio.style("reset")}{stdio.color("reset")} {message}`
	)
end

function Reporter.success(message: string)
	print(`\n  {stdio.color("green")}{stdio.style("bold")}{message}{stdio.style("reset")}{stdio.color("reset")}`)
end

return Reporter
