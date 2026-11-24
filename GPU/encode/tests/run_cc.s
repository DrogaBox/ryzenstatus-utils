# run_cc(entry, regs): runs code at `entry` with rbx, rbp, r12 and r15 taken from regs[0..3]; the code ends at
# an exit marker, "push <id>; pop r10; jmp r11". Afterwards regs[4] = r10 (the exit id), regs[5..8] = rdi, rsi,
# rdx, rax and regs[9..10] = r12, r15.
	.text
	.globl	_run_cc
_run_cc:
	pushq	%rbp
	pushq	%rbx
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15
	pushq	%rsi
	subq	$0x40, %rsp
	movq	%rdi, %rax
	movq	0(%rsi), %rbx
	movq	8(%rsi), %rbp
	movq	16(%rsi), %r12
	movq	24(%rsi), %r15
	xorl	%r10d, %r10d
	leaq	1f(%rip), %r11
	jmpq	*%rax
1:
	movq	0x40(%rsp), %rcx
	movq	%r10, 32(%rcx)
	movq	%rdi, 40(%rcx)
	movq	%rsi, 48(%rcx)
	movq	%rdx, 56(%rcx)
	movq	%rax, 64(%rcx)
	movq	%r12, 72(%rcx)
	movq	%r15, 80(%rcx)
	addq	$0x40, %rsp
	popq	%rsi
	popq	%r15
	popq	%r14
	popq	%r13
	popq	%r12
	popq	%rbx
	popq	%rbp
	retq
