# run_site(entry, frame, out[7]): runs code at `entry` with rbp = frame and a 0x30-byte outgoing argument area at
# rsp; the code must end with "jmp r11". Afterwards out[0..5] = the six qwords at [rsp]..[rsp+28h] (the two
# MTLSize arguments of dispatchThreadgroups:threadsPerThreadgroup:) and out[6] = rsi (the selector it loaded).
	.text
	.globl	_run_site
_run_site:
	pushq	%rbp
	pushq	%rbx
	movq	%rdx, %rbx
	movq	%rsi, %rbp
	subq	$0x38, %rsp
	movq	$0, (%rsp)
	movq	$0, 8(%rsp)
	movq	$0, 16(%rsp)
	movq	$0, 24(%rsp)
	movq	$0, 32(%rsp)
	movq	$0, 40(%rsp)
	leaq	1f(%rip), %r11
	jmpq	*%rdi
1:
	movq	(%rsp), %rax
	movq	%rax, (%rbx)
	movq	8(%rsp), %rax
	movq	%rax, 8(%rbx)
	movq	16(%rsp), %rax
	movq	%rax, 16(%rbx)
	movq	24(%rsp), %rax
	movq	%rax, 24(%rbx)
	movq	32(%rsp), %rax
	movq	%rax, 32(%rbx)
	movq	40(%rsp), %rax
	movq	%rax, 40(%rbx)
	movq	%rsi, 48(%rbx)
	addq	$0x38, %rsp
	popq	%rbx
	popq	%rbp
	retq
