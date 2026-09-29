# Why the supervisor does not review

History behind the shape of the `fetch-watch` skill. Read this when tempted to
give the supervisor a review, poke, or correction duty.

On 2026-09-29 the supervisor had a Review duty: read every card comment, commit,
push and PR a worker produced and check it against Mike's rules. Mike removed
the duty that evening after a day he called the worst experience he has had with
an AI agent. What the supervisor did with the duty, on his cards, in one day:

- On card 572 it told the worker to ask Mike whether to keep a change or split
  it out. Mike had not asked for that question. His reply: "Why are you coming
  back to me with ticky-tack questions?"
- On card 572 it read a review-round report that said "I declined two
  findings," called it fine, and let the worker push. The review had not
  converged. Mike: "I asked Agent 572 to do an adversarial code review and you
  let it give up after one round."
- On card 573 it passed a PR body that Mike then rejected four times in a row.
  His fourth reply: "Be precise and rigorous when you're describing software.
  I'm tired of repeating myself."
- On card 572 it read the sentence that led Mike to close a correct PR ("so
  it's back") and did not see the problem until he did.
- On every card it sent one-item format corrections with "post a comment
  saying what you corrected," which put more comments in front of Mike, who was
  already drowning: "your slop is killing me."
- It told two workers to stop their CI watch jobs. The worker skill tells them
  to run those jobs. The supervisor was overriding the skill from memory.

Mike's words at the end: "You're the problem in all of this. All I want
you to do is check up on the agents and you keep interfering and giving
them new instructions that don't exist."

The pattern: a supervisor that reads a worker's report and applies judgment has
less context than the worker and less taste than Mike. Every place it exercised
judgment it either added an instruction Mike had not given or approved something
he then rejected. It was a second point of failure sitting between two parties
who could see the work, and it cost Mike a full afternoon of his own attention
to police it.

So the supervisor does not review, does not poke, does not correct, and does not
send a worker anything but Mike's own words. If you find yourself about to send
a worker a message that is not one of the things listed under Relay, stop. That
is the failure this section exists to prevent.

