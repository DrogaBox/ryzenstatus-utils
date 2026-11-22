// controltest - checks the GPU control's decisions
// (sensors/kext/control_logic.hpp) without a GPU or a kernel. Exit status 0 =
// every check passed.
#include <stdint.h>
#include <stdio.h>

#include "control_logic.hpp"

static int failures = 0;
static void check(bool ok, const char* what) {
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) failures++;
}

using namespace gpuctl;

// An armed Owner whose client 7 holds a change made at `t`.
static Owner changedAt(uint64_t t) {
  Owner o;
  o.arm();
  o.change(7, t);
  return o;
}

static void card() {
  check(deviceAllowed(0x1002, 0x73BF, 0xC1),
        "the RX 6800 XT (73BF rev C1) is allowed");
  check(!deviceAllowed(0x1002, 0x73BF, 0xC0),
        "an RX 6900 XT (73BF rev C0) is not");
  check(!deviceAllowed(0x1002, 0x73BF, 0xC3),
        "an RX 6800 (73BF rev C3) is not");
  check(!deviceAllowed(0x1002, 0x73AF, 0xC0),
        "an RX 6900 XT XTXH (73AF) is not");
  check(!deviceAllowed(0x1002, 0x73FF, 0xC1), "a Navi 23 card is not");
  check(!deviceAllowed(0x10DE, 0x73BF, 0xC1),
        "the same ids from another vendor are not");
}

static void profiles() {
  check(profileAllowed(0) && profileAllowed(2) && profileAllowed(16),
        "automatic, power saving and compute are allowed");
  check(!profileAllowed(1) && !profileAllowed(4),
        "3D and video wait until the first three are measured");
  check(!profileAllowed(8) && !profileAllowed(32),
        "VR and custom are never allowed");
  check(!profileAllowed(3) && !profileAllowed(18),
        "mixes of bits are not profiles");
  uint32_t p = 99;
  check(parseProfileArg("0", &p) && p == 0, "gpuprofile=0 is automatic");
  check(parseProfileArg("2", &p) && p == 2, "gpuprofile=2 is power saving");
  check(parseProfileArg("16", &p) && p == 16, "gpuprofile=16 is compute");
  check(parseProfileArg("002", &p) && p == 2,
        "leading zeros within 3 digits are fine");
  p = 99;
  const char* bad[] = {"",
                       "32",
                       "8",
                       "-2",
                       "+2",
                       "0x10",
                       "1e1",
                       "16 ",
                       " 16",
                       "016x",
                       "0016",
                       "2.0",
                       "4",
                       "1",
                       "16\n",
                       "\xff",
                       "\xb2",
                       "99999999999999999999",
                       "18446744073709551632"};
  bool none = true;
  for (const char* b : bad) none = none && !parseProfileArg(b, &p);
  check(none && p == 99,
        "malformed or refused gpuprofile values change nothing");
  check(!parseProfileArg(nullptr, &p) && !parseProfileArg("2", nullptr),
        "null arguments are refused");
}

// The floors below are the card's (powerRange): 225 W is the owner's RX 6800
// XT (240 W start-up, PowerPercent -6), 248 W a stock one (264 W, -6).
static void power() {
  check(checkPower(240, 225, 230) == PowerCheck::Ok,
        "230 W under a 240 W start-up with a 225 W floor is taken");
  check(checkPower(240, 200, 200) == PowerCheck::Ok,
        "the floor itself is taken when it is a 10 W step");
  check(checkPower(240, 225, 240) == PowerCheck::Ok,
        "the start-up value is taken (going back)");
  check(checkPower(264, 248, 264) == PowerCheck::Ok,
        "a start-up value off the 10 W grid is taken");
  check(checkPower(264, 248, 260) == PowerCheck::Ok,
        "260 W under 264 W is taken");
  check(checkPower(300, 282, 300) == PowerCheck::Ok,
        "300 W is the highest believable start-up value");
  check(checkPower(240, 225, 250) == PowerCheck::AboveBoot,
        "above the start-up value is refused");
  check(checkPower(240, 225, 241) == PowerCheck::AboveBoot,
        "1 W above is refused");
  check(checkPower(240, 225, UINT32_MAX) == PowerCheck::AboveBoot,
        "the largest request is refused");
  check(checkPower(240, 225, 240000) == PowerCheck::AboveBoot,
        "a request in milliwatts is refused");
  check(checkPower(240, 225, 220) == PowerCheck::BelowFloor,
        "220 W under a 225 W floor is refused");
  check(checkPower(240, 225, 200) == PowerCheck::BelowFloor,
        "200 W (the old project floor) is refused under the card's 225 W");
  check(checkPower(240, 225, 224) == PowerCheck::BelowFloor,
        "1 W under the floor is refused");
  check(checkPower(240, 225, 0) == PowerCheck::BelowFloor, "0 W is refused");
  check(checkPower(240, 225, 235) == PowerCheck::NotAStep,
        "235 W is not a 10 W step");
  check(checkPower(240, 0, 230) == PowerCheck::NoFloor &&
            checkPower(240, 0, 0) == PowerCheck::NoFloor,
        "with the card's floor not known nothing below the start-up value is "
        "taken");
  check(checkPower(240, 0, 250) == PowerCheck::AboveBoot &&
            checkPower(240, 0, UINT32_MAX) == PowerCheck::AboveBoot,
        "above the start-up value is AboveBoot, floor known or not");
  check(checkPower(240, 0, 240) == PowerCheck::Ok,
        "the way back needs no floor");
  check(checkPower(240, 241, 230) == PowerCheck::NoFloor,
        "a floor above the start-up value is not believed");
  check(checkPower(0, 225, 230) == PowerCheck::NoBootValue,
        "nothing is taken before the start-up value is read");
  check(checkPower(0, 0, 0) == PowerCheck::NoBootValue,
        "an unread start-up value is never matched by 0");
  check(checkPower(199, 190, 199) == PowerCheck::NoBootValue,
        "a start-up value under 200 W is not believed");
  check(checkPower(301, 280, 250) == PowerCheck::NoBootValue,
        "a start-up value over 300 W is not believed");
  check(checkPower(380, 350, 350) == PowerCheck::NoBootValue,
        "a corrupt high start-up value is not believed");
  check(checkPower(240000, 225, 230) == PowerCheck::NoBootValue,
        "a start-up value in milliwatts is not believed");
  check(checkPower(200, 188, 200) == PowerCheck::Ok,
        "a 200 W start-up allows going back");
  check(checkPower(200, 188, 190) == PowerCheck::Ok &&
            checkPower(200, 188, 180) == PowerCheck::BelowFloor &&
            checkPower(200, 188, 210) == PowerCheck::AboveBoot,
        "a 200 W start-up takes its own floor, nothing lower or higher");
}
static void arming() {
  Owner o;
  check(o.change(7, 1000) == Ask::NotArmed, "the control starts closed");
  check(o.arm() && o.isArmed(), "an administrator opens it");
  check(o.change(0, 1000) == Ask::BadClient, "client 0 is never an owner");
  check(o.change(7, 1000) == Ask::Ok && o.owner() == 7,
        "the first change makes its program the owner");
  check(o.change(7, 1000) == Ask::TooSoon, "the same time again is too soon");
  check(o.change(8, 5000) == Ask::Busy, "a second program gets busy");
  check(o.change(7, 2999) == Ask::TooSoon, "1.999 s later is too soon");
  check(o.change(7, 3000) == Ask::Ok, "2 s later is taken");
  check(o.change(7, 2000) == Ask::Busy,
        "a change dated before the owner's last one is refused");
  o.turnOff();
  check(!o.arm() && !o.isArmed(),
        "a control turned off cannot be opened again");
}

static void silence() {
  Owner o = changedAt(0);  // a change at time 0 counts like any other
  check(o.owner() == 7 && o.isChanged(), "a change at time 0 is held");
  check(!o.alive(8, 1000), "only the owner can say it is still there");
  check(o.alive(7, 20000), "the owner says it is still there");
  check(!o.alive(7, 10000), "a word dated before the last one is ignored");
  check(o.change(7, 10000) == Ask::Busy, "nor a change dated before it");
  check(o.expired(49999) == 0, "29.999 s after its last word the change stays");
  check(!o.alive(7, 50000), "a word 30 s late does not save the change");
  check(o.change(7, 50000) == Ask::Busy, "nor a change 30 s late");
  uint64_t id = o.expired(50000);
  check(id != 0 && o.owner() == 0 && o.isReverting(),
        "30 s of silence: everything goes back");
  check(o.expired(90000) == 0, "it goes back once, not again");
  check(o.change(8, 90000) == Ask::Busy, "no change while the way back runs");
  o.reverted(id + 1, 90000);
  check(o.isReverting(), "a report for another way back is ignored");
  o.reverted(id, 90000);
  check(!o.isReverting() && !o.isChanged(), "the way back finished");
  check(o.change(8, 91000) == Ask::TooSoon,
        "a change right after the way back waits 2 s");
  check(o.change(8, 92000) == Ask::Ok, "then another program can change");
  check(o.expired(10000) == 0,
        "a timer time earlier than the last word expires nothing");
}
static void closing() {
  Owner o = changedAt(1000);
  check(o.closed(8) == 0, "another connection closing changes nothing");
  check(o.release(8) == 0, "another program cannot put things back");
  uint64_t id = o.closed(7);
  check(id != 0 && o.owner() == 0,
        "the owner's connection closing puts everything back at once");
  check(o.closed(7) == 0 && o.release(7) == 0, "closing twice does it once");
  check(o.change(9, 1500) == Ask::Busy,
        "a relaunched program waits for the way back");
  o.reverted(id, 1600);
  check(o.change(9, 3500) == Ask::TooSoon, "and then 2 s from the way back");
  check(o.change(9, 3600) == Ask::Ok, "then it can change");
  uint64_t id2 = o.release(9);
  check(id2 != 0 && id2 != id && o.isReverting(),
        "the owner can put everything back itself");
  o.reverted(id2, 500);
  check(o.change(9, 4000) == Ask::TooSoon,
        "a way back reported with an older time keeps the 2 s gap");
  check(o.expired(1000000) == 0, "nothing expires without an owner");
}
static void sleeping() {
  {
    Owner o = changedAt(1000);
    o.willSleep();
    check(o.owner() == 0 && o.isSleeping(),
          "before sleep the owner is forgotten");
    check(o.change(7, 10000) == Ask::Sleeping, "no change while asleep");
    check(o.expired(100000) == 0 && o.closed(7) == 0 && o.release(7) == 0 &&
              !o.alive(7, 2000),
          "nothing is sent while asleep");
    uint64_t id = o.didWake();
    check(id != 0 && o.isReverting(),
          "after wake the start-up values are sent");
    check(o.didWake() == 0, "a second wake notice sends nothing");
    check(o.change(7, 200000) == Ask::Busy,
          "no change until the way back finished");
    o.reverted(id, 200000);
    check(o.change(7, 202000) == Ask::Ok, "after that changes work again");
  }
  {
    Owner o;
    o.arm();
    o.willSleep();
    check(o.didWake() == 0,
          "nothing is sent after wake when nothing was changed");
  }
  {
    Owner o = changedAt(1000);
    check(o.didWake() == 0 && o.owner() == 7 && !o.isReverting(),
          "a wake notice without a sleep leaves a held change alone");
  }
  {
    Owner o = changedAt(1000);
    uint64_t before = o.closed(7);
    check(before != 0, "a way back starts");
    o.willSleep();
    check(!o.isReverting(), "sleep drops a way back that had not run");
    o.revertFailed(before);
    check(!o.isOff(),
          "a failure report for a way back sleep dropped is ignored");
    o.reverted(before, 1500);
    check(o.isChanged(), "that way back finishing during sleep does not count");
    uint64_t after = o.didWake();
    check(after != 0 && after != before,
          "it runs again after wake, with a new number");
    o.reverted(before, 2000);
    check(o.isReverting(),
          "the old way back finishing late does not end the new one");
    o.reverted(after, 2100);
    check(o.change(8, 4100) == Ask::Ok,
          "the new one finishing does; another program changes");
    o.reverted(after, 4200);
    check(o.isChanged() && o.owner() == 8,
          "a repeated report cannot clear that change");
    check(o.closed(8) != 0, "so closing it still puts everything back");
  }
  {
    Owner o = changedAt(1000);
    o.turnOff();
    o.willSleep();
    check(o.didWake() == 0, "a control turned off sends nothing after wake");
  }
  {
    Owner o = changedAt(1000);
    o.willSleep();
    o.turnOff();
    check(o.didWake() == 0, "nor when it was turned off while asleep");
  }
}
static void failing() {
  Owner o = changedAt(1000);
  uint64_t id = o.release(7);
  check(id != 0, "a failed write goes back");
  o.revertFailed(id + 1);
  check(!o.isOff(), "a failure report for another way back is ignored");
  o.revertFailed(id);
  check(o.isOff() && o.owner() == 0 && !o.isReverting(),
        "a failed way back turns the control off");
  check(o.change(7, 100000) == Ask::Off, "off stays off");
}
// ------------------------------------------------------------ 0.5.0 writes --

static void escapes() {
  EscapeHeader q = accessQuery();
  check(q.size == 16 && q.code == 0x00C0002A && q.reserved0 == 0 &&
            q.reserved1 == 0,
        "0x2a is a bare 16-byte header {16, 0x00C0002A, 0, 0}");
  AccessOut a = accessAnswer();
  check(a.size == 12 && a.accessible == 0 && a.unused == 0,
        "the 0x2a answer starts as {12, 0, 0}");
  SetLimitIn s{};
  check(makeSetLimit(240, 225, 230, &s) && s.header.size == 16 &&
            s.header.code == 0x00C0006E && s.header.reserved0 == 0 &&
            s.header.reserved1 == 0 && s.size == 8 && s.watts == 230,
        "0x6e is {16, 0x00C0006E, 0, 0} + {8, watts}");
  check(makeSetLimit(240, 225, 240, &s) && s.watts == 240 &&
            makeSetLimit(240, 0, 240, &s) && s.watts == 240,
        "0x6e with the start-up value is built (the way back), floor or not");
  SetLimitIn untouched{};
  bool none = !makeSetLimit(240, 225, 250, &untouched) &&
              !makeSetLimit(240, 225, 220, &untouched) &&
              !makeSetLimit(240, 225, 200, &untouched) &&
              !makeSetLimit(240, 225, 235, &untouched) &&
              !makeSetLimit(240, 0, 230, &untouched) &&
              !makeSetLimit(0, 225, 230, &untouched) &&
              !makeSetLimit(400, 300, 300, &untouched) &&
              !makeSetLimit(240, 225, 230, nullptr);
  check(none && untouched.watts == 0 && untouched.header.code == 0,
        "no 0x6e is built outside the range, whatever the caller checked");
  check(kCwddeBytes == 24 && kCwddeEntry[0] == 0x55 &&
            kCwddeEntry[kCwddeBytes - 1] == 0x00,
        "ppCWDDE's expected entry is 24 bytes, starting with push rbp");
}

static void answers() {
  AccessOut up{12, 1, 0}, down{12, 0, 0}, odd{12, 2, 0}, small{8, 1, 0};
  check(classifyAccess(0, 12, up) == Access::Yes, "0 + accessible 1 is up");
  check(classifyAccess(0, 12, down) == Access::No,
        "0 + accessible 0 is asleep or blocked");
  check(classifyAccess(kRetUnsupported, 12, up) == Access::No &&
            classifyAccess(kRetError, 12, up) == Access::No,
        "not initialized or busy is not accessible");
  check(classifyAccess(0, 8, up) == Access::Error &&
            classifyAccess(0, 12, small) == Access::Error &&
            classifyAccess(0, 12, odd) == Access::Error &&
            classifyAccess(0xE00002C2, 12, up) == Access::Error,
        "an answer that does not fit the escape is an error");
  check(classifySend(0, SendSeen{1, 200, 0}, 200) == Sent::Confirmed,
        "one send of the watts asked, taken: confirmed");
  check(classifySend(kRetError, SendSeen{0, 0, 0}, 200) == Sent::NotSent &&
            classifySend(kRetUnsupported, SendSeen{0, 0, 0}, 200) ==
                Sent::NotSent,
        "busy or not ready with nothing sent: not sent");
  check(classifySend(0, SendSeen{0, 0, 0}, 200) == Sent::Failed,
        "an escape that says done without a send seen fails");
  check(classifySend(0, SendSeen{1, 210, 0}, 200) == Sent::Failed &&
            classifySend(0, SendSeen{1, 200, 2}, 200) == Sent::Failed &&
            classifySend(0, SendSeen{2, 200, 0}, 200) == Sent::Failed &&
            classifySend(kRetError, SendSeen{1, 200, 0}, 200) == Sent::Failed,
        "other watts, a firmware error, two sends or an error after a send "
        "fail");
}

static void routing() {
  check(routeSet(240, 225, 240) == SetRoute::Release &&
            routeSet(240, 0, 240) == SetRoute::Release,
        "set(start-up value) is routed to release, not a change, floor or "
        "not");
  check(routeSet(264, 248, 264) == SetRoute::Release, "also off the 10 W grid");
  check(routeSet(240, 225, 230) == SetRoute::Change, "set(230) is a change");
  check(routeSet(240, 225, 250) == SetRoute::Refuse &&
            routeSet(240, 225, 220) == SetRoute::Refuse &&
            routeSet(240, 225, 235) == SetRoute::Refuse &&
            routeSet(240, 0, 230) == SetRoute::Refuse &&
            routeSet(0, 0, 0) == SetRoute::Refuse,
        "out of range is refused, also before the start-up value or the "
        "floor is known");
  // set(bootW) through release: the program drops what it held and the way
  // back runs; nothing is counted as a change.
  Owner o = changedAt(1000);
  uint64_t id = routeSet(240, 225, 240) == SetRoute::Release ? o.release(7) : 0;
  check(id != 0 && o.owner() == 0 && o.isReverting(),
        "set(start-up value) by the owner goes back");
  Owner idle;
  idle.arm();
  check(idle.release(7) == 0 && !idle.isChanged() && idle.owner() == 0,
        "set(start-up value) with nothing held sends nothing, owns nothing");
}

static void asking() {
  Owner o;
  check(o.wouldChange(7, 1000) == Ask::NotArmed,
        "the pre-check sees a closed control");
  o.arm();
  check(o.wouldChange(0, 1000) == Ask::BadClient &&
            o.wouldChange(7, 1000) == Ask::Ok && o.owner() == 0 &&
            !o.isChanged(),
        "the pre-check changes nothing");
  o.change(7, 1000);
  bool same = true;
  const uint64_t times[] = {1000, 2999, 3000, 40000}, clients[] = {0, 7, 8};
  for (uint64_t t : times)
    for (uint64_t c : clients) {
      Owner copy = o;
      Ask pre = copy.wouldChange(c, t);
      same = same && pre == copy.change(c, t);
    }
  check(same, "the pre-check answers what change answers");
  check(o.deadline() == 31000, "the deadline is the last word + 30 s");
  o.alive(7, 20000);
  check(o.deadline() == 50000, "a word moves it");
  check(o.expired(o.deadline() - 1) == 0,
        "waking 1 ms before the deadline expires nothing");
  uint64_t id = o.expired(o.deadline());
  check(id != 0 && o.isReverting(),
        "the worker waking at the deadline takes the change back");
  check(o.deadline() == 0, "nobody owns it: no deadline");
  Owner fresh;
  check(fresh.deadline() == 0, "no deadline at start");
}

// The worker's pass over one request, with the steps the kext takes: 0x2a
// first, then under the state lock wanted() and change(), then 0x6e.
static void slot() {
  {
    SetSlot s;
    uint64_t t = s.post(7, 200);
    check(t != 0 && s.waiting(), "a request waits in the slot");
    check(s.post(8, 210) == 0 && s.post(7, 210) == 0,
          "a second request is refused while one waits");
    s.abandon(t);
    Reply r = Reply::Ok;
    check(s.empty() && s.collect(t, &r) && r == Reply::Cancelled,
          "a request given up before the worker took it is gone");
    uint64_t c = 0, tk = 0;
    uint32_t w = 0;
    check(!s.take(&tk, &c, &w), "the worker finds nothing to do");
  }
  {
    // Stale slot after a way back: the program timed out after the worker
    // took the request, and released what it held; the worker must not make
    // the change after that.
    Owner o = changedAt(1000);  // client 7 holds a change
    SetSlot s;
    uint64_t t = s.post(7, 200);
    uint64_t tk = 0, c = 0;
    uint32_t w = 0;
    check(s.take(&tk, &c, &w) && tk == t && c == 7 && w == 200,
          "the worker takes the request");
    s.abandon(t);  // 5 s passed while 0x2a ran
    uint64_t id = o.owner() == 7 ? o.release(7) : 0;
    check(id != 0, "the timed-out owner's change goes back");
    o.reverted(id, 7000);
    check(!s.wanted(tk), "after 0x2a the request is not wanted any more");
    s.finish(tk, Reply::Cancelled);
    check(s.empty() && !o.isChanged() && o.owner() == 0,
          "no change after the way back: the slot is free, nothing held");
    check(s.post(8, 200) != 0, "the next program can ask");
  }
  {
    // Timed out while 0x6e ran: the way back runs after it.
    Owner o;
    o.arm();
    SetSlot s;
    uint64_t t = s.post(7, 200);
    uint64_t tk = 0, c = 0;
    uint32_t w = 0;
    s.take(&tk, &c, &w);
    check(s.wanted(tk) && o.change(7, 1000) == Ask::Ok,
          "still wanted after 0x2a: the change is made");
    s.abandon(t);  // the program gives up while 0x6e is in flight
    uint64_t id = o.owner() == 7 ? o.release(7) : 0;
    check(id != 0 && o.isReverting(),
          "its way back is pending behind the running 0x6e");
    s.finish(tk, Reply::Ok);
    Reply r = Reply::Ok;
    check(s.empty() && s.collect(t, &r) && r == Reply::Cancelled,
          "the late answer is dropped");
    o.reverted(id, 1500);
    check(!o.isChanged(), "and the way back ends it");
  }
  {
    SetSlot s;
    uint64_t t = s.post(7, 200);
    uint64_t tk = 0, c = 0;
    uint32_t w = 0;
    s.take(&tk, &c, &w);
    Reply r = Reply::Cancelled;
    check(!s.collect(t, &r), "no answer while it runs");
    s.finish(tk + 1, Reply::Failed);
    check(!s.collect(t, &r), "a finish for another ticket is ignored");
    s.finish(tk, Reply::TooSoon);
    check(s.collect(t, &r) && r == Reply::TooSoon && s.empty(),
          "the answer reaches its program and frees the slot");
    uint64_t t2 = s.post(9, 210);
    check(t2 != 0 && t2 != t, "tickets are never reused");
    s.abandonClient(8);
    check(s.waiting(), "another connection closing leaves it");
    s.abandonClient(9);
    check(s.empty(), "its own connection closing drops it");
    check(s.post(0, 200) == 0, "client 0 never posts");
  }
  {
    // Its connection closes while 0x2a or 0x6e runs: the waiting set answers
    // at once, the slot stays taken until the worker finishes.
    SetSlot s;
    uint64_t t = s.post(7, 200);
    uint64_t tk = 0, c = 0;
    uint32_t w = 0;
    s.take(&tk, &c, &w);
    s.abandonClient(7);
    Reply r = Reply::Ok;
    check(s.collect(t, &r) && r == Reply::Cancelled,
          "a running request given up answers cancelled at once");
    check(!s.empty() && s.post(8, 200) == 0 && !s.wanted(tk),
          "the slot stays taken, and unwanted, while the call runs");
    s.finish(tk, Reply::Ok);
    check(s.empty() && s.post(8, 200) != 0,
          "the worker's finish frees it for the next program");
  }
}

static void retries() {
  check(tryResult(Access::No, Sent::Failed) == TryResult::Transient &&
            tryResult(Access::Yes, Sent::NotSent) == TryResult::Transient,
        "not accessible, or busy with nothing sent, is worth another try");
  check(tryResult(Access::Error, Sent::Confirmed) == TryResult::Failed &&
            tryResult(Access::Yes, Sent::Failed) == TryResult::Failed,
        "an odd 0x2a answer or a wrong send is not");
  check(tryResult(Access::Yes, Sent::Confirmed) == TryResult::Confirmed,
        "a confirmed send is done");
  check(afterRevertTry(1, TryResult::Transient, false) == Next::Retry &&
            afterRevertTry(2, TryResult::Transient, false) == Next::Retry,
        "tries 1 and 2 busy: try again in 500 ms");
  check(afterRevertTry(3, TryResult::Transient, false) == Next::GiveUp,
        "try 3 busy: give up (revertFailed, off)");
  check(afterRevertTry(1, TryResult::Failed, false) == Next::GiveUp,
        "a failed send gives up at once");
  check(afterRevertTry(1, TryResult::Transient, true) == Next::Abort &&
            afterRevertTry(1, TryResult::Failed, true) == Next::Abort,
        "a sleep starting stops the tries, nothing more is sent");
  check(afterRevertTry(3, TryResult::Confirmed, true) == Next::Done,
        "a confirmed way back is done even if a sleep starts after it");
  // Exhaustion end to end: three busy tries, then the control is off.
  Owner o = changedAt(1000);
  uint64_t id = o.closed(7);
  Next n = Next::Retry;
  uint32_t tries = 0;
  for (uint32_t i = 1; n == Next::Retry && i <= 10; i++) {
    tries = i;
    n = afterRevertTry(i, tryResult(Access::No, Sent::NotSent), false);
  }
  if (n == Next::GiveUp) o.revertFailed(id);
  check(tries == kRevertTries && n == Next::GiveUp && o.isOff(),
        "a way back busy three times turns the control off");
  check(kRevertTries == 3 && kRevertRetryMs == 500, "3 tries, 500 ms apart");
}

static void waking() {
  check(wakeWait(4, 4, false, 10, 10, 1000, 1000) == WakeWait::Keep,
        "right after wake: wait for the framebuffer's read");
  check(wakeWait(4, 4, false, 10, 11, 1000, 1200) == WakeWait::Done,
        "its read came: go on");
  check(wakeWait(4, 4, false, 10, 10, 1000, 10999) == WakeWait::Keep &&
            wakeWait(4, 4, false, 10, 10, 1000, 11000) == WakeWait::Done,
        "or after 10 s");
  check(wakeWait(4, 5, false, 10, 11, 1000, 1200) == WakeWait::Abort,
        "a sleep generation change during the wait aborts it, read or not");
  check(wakeWait(4, 4, true, 10, 10, 1000, 20000) == WakeWait::Abort,
        "a sleep in progress aborts it, even after 10 s");
  check(wakeWait(4, 4, false, 10, 10, 5000, 1000) == WakeWait::Keep,
        "a clock earlier than the start does not end the wait");
  // The worker after an abort: didWake is not called, the Owner stays asleep
  // and nothing is sent; the next wake runs the wait again.
  Owner o = changedAt(1000);
  o.willSleep();
  if (wakeWait(4, 5, false, 10, 10, 1000, 1200) == WakeWait::Done) o.didWake();
  check(o.isSleeping() && !o.isReverting() && o.isChanged(),
        "after an aborted wait nothing is sent and the change is remembered");
  // The next wake: the read comes at 3100, then 2 s of margin.
  bool read = wakeWait(5, 5, false, 11, 12, 3000, 3100) == WakeWait::Done;
  check(read && wakeMargin(5, 5, false, 3100, 3100) == WakeWait::Keep &&
            wakeMargin(5, 5, false, 3100, 5099) == WakeWait::Keep,
        "after the framebuffer's read: still 2 s before anything is sent");
  check(o.isSleeping() && !o.isReverting(), "nothing is sent in the margin");
  uint64_t id =
      wakeMargin(5, 5, false, 3100, 5100) == WakeWait::Done ? o.didWake() : 0;
  check(id != 0 && o.isReverting(),
        "2 s after the read the completed wake goes back");
}

static void margins() {
  check(kWakeReadyMarginMs == 2000, "the wake margin is 2 s");
  check(wakeMargin(4, 4, false, 1000, 2999) == WakeWait::Keep &&
            wakeMargin(4, 4, false, 1000, 3000) == WakeWait::Done,
        "the margin ends exactly 2 s after the read");
  check(wakeMargin(4, 5, false, 1000, 9000) == WakeWait::Abort &&
            wakeMargin(4, 4, true, 1000, 9000) == WakeWait::Abort,
        "a new sleep during the margin aborts it, even after 2 s");
  check(wakeMargin(4, 4, false, 5000, 1000) == WakeWait::Keep,
        "a clock earlier than the read does not end the margin");
  // After the 10 s timeout (no read) the margin still applies.
  check(wakeWait(4, 4, false, 10, 10, 0, 10000) == WakeWait::Done &&
            wakeMargin(4, 4, false, 10000, 11999) == WakeWait::Keep &&
            wakeMargin(4, 4, false, 10000, 12000) == WakeWait::Done,
        "a wake with no read waits 10 s, then 2 s more");
  check(kSleepWaitMs == 3000 && kSleepWaitMs > 2000,
        "ppSleep waits 3 s at most for a call in flight, more than one 2 s "
        "mailbox wait");
  check(kTeardownWaitMs == 2000 && kTeardownWaitMs < kSleepWaitMs,
        "GPU teardown waits at most 2 s for a call in flight");
}

static void prereqs() {
  WritePrereqs ok{false, 1, 1, true, true, true};
  check(staticRefusal(ok) == WriteOff::None, "everything in place: can arm");
  WritePrereqs p = ok;
  p.ctlOff = true;
  bool all = staticRefusal(p) == WriteOff::CtlOff;
  p = ok;
  p.allowedGpus = 0;
  all = all && staticRefusal(p) == WriteOff::NotOneCard;
  p.allowedGpus = 2;
  p.amdGpus = 2;
  all = all && staticRefusal(p) == WriteOff::NotOneCard;
  p = ok;
  p.amdGpus = 2;
  all = all && staticRefusal(p) == WriteOff::OtherAmdGpu;
  p = ok;
  p.x6000Library = false;
  all = all && staticRefusal(p) == WriteOff::Library;
  p = ok;
  p.routed = false;
  all = all && staticRefusal(p) == WriteOff::Routes;
  p = ok;
  p.cwddeChecked = false;
  all = all && staticRefusal(p) == WriteOff::Cwdde;
  check(all, "each missing prerequisite has its reason");
  // What the kext does with one: turnOff at start, so arm is refused.
  Owner o;
  if (staticRefusal(WritePrereqs{false, 1, 2, true, true, true}) !=
      WriteOff::None)
    o.turnOff();
  check(o.isOff() && !o.arm() && o.change(7, 1000) == Ask::Off,
        "a static failure turns the control off: arm and set are refused");
  bool texts = true;
  for (uint32_t w = 1; w <= static_cast<uint32_t>(WriteOff::ReadOnlyCard); w++)
    texts = texts && writeOffText(static_cast<WriteOff>(w))[0] != '\0';
  check(texts, "every reason has a text");
}

static void channel() {
  check(kChannelVersion == 2 && kSelStatus == 0 && kSelRelease == 4 &&
            kSelSetOd8 == 5 && kSelDisarm == 6 && kSelCount == 7 &&
            kStReply == 0 && kStLastReply == 8 && kStOd8Check == 12 &&
            kStatusCount == 13,
        "the channel's numbers are the documented ones (version 2)");
  check(replyFor(Ask::Ok) == Reply::Ok && replyFor(Ask::Busy) == Reply::Busy &&
            replyFor(Ask::TooSoon) == Reply::TooSoon &&
            replyFor(Ask::Off) == Reply::Off &&
            replyFor(Ask::NotArmed) == Reply::NotArmed &&
            replyFor(Ask::Sleeping) == Reply::Sleeping &&
            replyFor(Ask::BadClient) == Reply::BadArgs,
        "every Owner answer has its reply");
  check(replyFor(PowerCheck::BelowFloor) == Reply::BelowFloor &&
            replyFor(PowerCheck::AboveBoot) == Reply::AboveBoot &&
            replyFor(PowerCheck::NotAStep) == Reply::NotAStep &&
            replyFor(PowerCheck::NoBootValue) == Reply::NoBootValue &&
            replyFor(PowerCheck::NoFloor) == Reply::NoFloor,
        "every range answer has its reply");
  bool texts = true;
  for (uint32_t r = 0; r <= static_cast<uint32_t>(Reply::NoFloor); r++)
    texts = texts && replyText(r)[0] != '\0';
  check(texts && replyText(999)[0] != '\0',
        "every reply has a text, an unknown one too");
}

// A 0x9f answer the way report.md 11.3/11.5 expects it on this card.
static void goodInitial(Od8InitialOut* o) {
  od8PrepareInitial(o);
  o->caps = 0x2000 | 0x200 | 0x8 | 0x4 | 0x1;
  for (uint32_t i = 0; i < kOd8Count; i++) o->e[i] = Od8Entry{};
  o->e[0] = Od8Entry{0x1, 500, 2800, 2575, 0, 0};
  o->e[1] = Od8Entry{0x1, 500, 2800, 500, 0, 0};
  o->e[9] = Od8Entry{0x8, -6, 9, 0, 0, 0};
  o->e[12] = Od8Entry{0, 25, 110, 70, 0, 0};  // hidden, still filled
  o->e[15] = Od8Entry{0x200, 0, 1, 1, 0, 0};
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    o->e[od8CurveTempId(k)] =
        Od8Entry{0x2000, 25, 100, int32_t(30 + 10 * k), 0, 0};
    o->e[od8CurveSpeedId(k)] =
        Od8Entry{0x2000, 20, 100, int32_t(20 + 20 * k), 0, 0};
  }
}

static void od8() {
  EscapeHeader q = od8Query(kEscapeOd8Initial);
  check(q.size == 16 && q.code == 0x00C0009F && q.reserved0 == 1 &&
            q.reserved1 == 0,
        "0x9f header {16, 0x00C0009F, 1 = not kept for replay, 0}");
  q = od8Query(kEscapeOd8Current);
  check(q.code == 0x00C000A0 && q.reserved0 == 1, "0xa0 header likewise");

  Od8InitialOut in;
  od8PrepareInitial(&in);
  check(in.count == 38 && in.caps == 0 && in.e[0].feature == kOd8Sentinel &&
            in.e[37].def == 0 && in.unused[1] == 0,
        "0x9f buffer: count 38 (never the size), zeroed, sentinel in entry 0");
  Od8CurrentOut cur;
  od8PrepareCurrent(&cur);
  check(cur.count == 38 && cur.cur[0] == int32_t(kOd8Sentinel) &&
            cur.cur[37] == 0 && cur.untouched == kOd8Sentinel,
        "0xa0 buffer: count 38, sentinel first and in the word never written");

  uint32_t odd = 99;
  check(od8CheckInitial(kRetOK, 928, in, &odd) == Od8Read::NoData && odd == 0,
        "0x9f answered 0 but wrote nothing: no data (asleep)");
  check(od8CheckCurrent(kRetOK, 164, cur, &odd) == Od8Read::NoData,
        "0xa0 likewise");
  check(od8CheckInitial(kRetError, 928, in, &odd) == Od8Read::Refused,
        "0xE00002BC: refused (OD8 off, or busy)");
  check(od8CheckInitial(kRetUnsupported, 928, in, &odd) == Od8Read::Unsupported,
        "0xE00002C7: not initialized");
  check(od8CheckInitial(kRetOK, 920, in, &odd) == Od8Read::Error,
        "another out size: error");
  check(od8CheckInitial(0x1234, 928, in, &odd) == Od8Read::Error,
        "an unknown answer: error");

  goodInitial(&in);
  check(od8CheckInitial(kRetOK, 928, in, &odd) == Od8Read::Ok && odd == 0,
        "the expected 0x9f answer: ok");
  Od8InitialOut bad = in;
  bad.count = 0;
  check(od8CheckInitial(kRetOK, 928, bad, &odd) == Od8Read::Odd && odd == 40,
        "count word changed: odd (40)");
  bad = in;
  bad.caps = 0x40000;
  check(od8CheckInitial(kRetOK, 928, bad, &odd) == Od8Read::Odd && odd == 39,
        "an unknown caps bit: odd (39)");
  bad = in;
  bad.e[9].feature = 0x1;
  check(od8CheckInitial(kRetOK, 928, bad, &odd) == Od8Read::Odd && odd == 10,
        "setting 9 with another setting's feature bit: odd (entry 10)");
  bad = in;
  bad.e[20].zero1 = 5;
  check(od8CheckInitial(kRetOK, 928, bad, &odd) == Od8Read::Odd && odd == 21,
        "a reserved word not 0: odd (the layout moved)");
  bad = in;
  bad.e[0].min = 3000;
  check(od8CheckInitial(kRetOK, 928, bad, &odd) == Od8Read::Odd && odd == 1,
        "an offered setting with min above max: odd");
  bad = in;
  bad.e[12].min = 200;  // hidden: not checked
  check(od8CheckInitial(kRetOK, 928, bad, &odd) == Od8Read::Ok,
        "a hidden setting (feature 0) is not range-checked");
  bad = in;
  bad.unused[0] = 1;
  check(od8CheckInitial(kRetOK, 928, bad, &odd) == Od8Read::Odd && odd == 41,
        "the unused tail written: odd (41)");

  od8PrepareCurrent(&cur);
  for (uint32_t i = 0; i < kOd8Count; i++) cur.cur[i] = in.e[i].def;
  cur.notAllowed = ~0x3FFFFu;
  check(od8CheckCurrent(kRetOK, 164, cur, &odd) == Od8Read::Ok,
        "the expected 0xa0 answer: ok");
  Od8CurrentOut badc = cur;
  badc.untouched = 0;
  check(od8CheckCurrent(kRetOK, 164, badc, &odd) == Od8Read::Odd && odd == 41,
        "0xa0 wrote past its 40 words: odd (41)");
  badc = cur;
  badc.count = 37;
  check(od8CheckCurrent(kRetOK, 164, badc, &odd) == Od8Read::Odd && odd == 40,
        "0xa0 count changed: odd (40)");
  check(od8CheckCurrent(kRetOK, 160, cur, &odd) == Od8Read::Error,
        "0xa0 another out size: error");

  check(od8Retry(Od8Read::NoData) && od8Retry(Od8Read::NotCalled) &&
            od8Retry(Od8Read::Refused) && od8Retry(Od8Read::Unsupported),
        "asleep, not called, refused, not initialized: tried again");
  check(!od8Retry(Od8Read::Ok) && !od8Retry(Od8Read::Odd) &&
            !od8Retry(Od8Read::Error),
        "data or an answer that does not fit: not tried again");

  Od8InitialOut moved = in;
  check(od8SameDefaults(in, moved), "same defaults: same");
  moved.e[0].def = 2400;
  check(!od8SameDefaults(in, moved), "a default that moved: not the same");
  Od8CurrentOut later = cur;
  check(od8SameCurrent(cur, later), "same current values: same");
  later.cur[15] = 0;
  check(!od8SameCurrent(cur, later), "zero RPM changed: not the same");

  bool features = true;
  for (uint32_t i = 0; i < kOd8Count; i++)
    if ((od8Feature(i) & ~kOd8KnownFeatures) != 0 || od8Feature(i) == 0 ||
        (od8Feature(i) & (od8Feature(i) - 1)) != 0)
      features = false;
  check(features, "every setting id has one known feature bit");
  check(od8Feature(19) == 0x2000 && od8Feature(28) == 0x2000 &&
            od8Feature(35) == 0x200 && od8Feature(34) == 0x4 &&
            od8Feature(37) == 0x20000 && od8Feature(10) == 0x20 &&
            od8Feature(11) == 0x10,
        "feature bits as report.md 11.2 (curve, zero RPM, UCLK min, fan min "
        "speed 0x20, acoustic 0x10)");
  check(od8CurveTempId(0) == 19 && od8CurveSpeedId(4) == 28 &&
            od8Name(19)[8] == '1' && od8Name(28)[8] == '5',
        "fan curve ids 19..28, temperature then speed");
}

// The OD8 data this card gave on 2026-11-19 (phase A, ioreg), as 0x9f/0xa0.
static void cardInitial(Od8InitialOut* o) {
  od8PrepareInitial(o);
  o->caps = 0x33f0d;
  for (uint32_t i = 0; i < kOd8Count; i++) o->e[i] = Od8Entry{};
  o->e[0] = Od8Entry{0x1, 500, 2800, 2354, 0, 0};
  o->e[1] = Od8Entry{0x1, 500, 2800, 500, 0, 0};
  o->e[8] = Od8Entry{0x4, 2000, 2150, 2000, 0, 0};
  o->e[9] = Od8Entry{0x8, -6, 9, 0, 0, 0};
  o->e[10] = Od8Entry{0, 1200, 3500, 700, 0, 0};
  o->e[11] = Od8Entry{0, 1200, 3500, 3500, 0, 0};
  o->e[12] = Od8Entry{0, 25, 100, 70, 0, 0};
  o->e[14] = Od8Entry{0x100, 0, 1, 0, 0, 0};
  o->e[15] = Od8Entry{0x200, 0, 1, 1, 0, 0};
  o->e[16] = Od8Entry{0x400, 0, 1, 0, 0, 0};
  o->e[17] = Od8Entry{0x800, 0, 1, 0, 0, 0};
  o->e[18] = Od8Entry{0x1000, 0, 1, 0, 0, 0};
  const int32_t T[5] = {30, 50, 56, 63, 70}, S[5] = {20, 36, 52, 68, 100};
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    o->e[od8CurveTempId(k)] = Od8Entry{0x2000, 25, 100, T[k], 0, 0};
    o->e[od8CurveSpeedId(k)] = Od8Entry{0x2000, 20, 100, S[k], 0, 0};
  }
  o->e[35] = Od8Entry{0x200, 30, 30, 30, 0, 0};
  o->e[36] = Od8Entry{0x10000, 0, 3, 3, 0, 0};
  o->e[37] = Od8Entry{0x20000, 881, 1075, 1075, 0, 0};
}
static void cardCurrent(const Od8InitialOut& in, Od8CurrentOut* c) {
  od8PrepareCurrent(c);
  for (uint32_t i = 0; i < kOd8Count; i++) c->cur[i] = in.e[i].def;
  for (uint32_t i = 10; i <= 13; i++) c->cur[i] = 0;  // hidden: current 0
  c->notAllowed = 0xfffcc0f2;
}
static Od8Want curveWant(const int32_t t[5], const int32_t s[5]) {
  Od8Want w{};
  w.curve = true;
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    w.temp[k] = t[k];
    w.speed[k] = s[k];
  }
  return w;
}

static void od8Writes() {
  Od8InitialOut first, fresh;
  cardInitial(&first);
  fresh = first;
  Od8CurrentOut cur;
  cardCurrent(first, &cur);

  // The stock state: the one fixed way back.
  Od8Want stock{};
  check(od8IsStock(stock), "no curve, zero RPM on, GFX 0: the stock state");
  check(od8CheckWant(stock, first, fresh, cur) == Od8Check::Ok,
        "the stock state passes the checks on this card");
  Od8SetIn in;
  od8Build(stock, first, fresh, &in);
  check(od8ShapeOk(in), "the stock call has the allowed shape");
  check(in.header.size == 16 && in.header.code == 0x00C000A1 &&
            in.header.reserved0 == 1 && in.count == 38,
        "0xa1 header {16, 0x00C000A1, 1 = not kept for replay, 0}, count 38");
  bool reset = true;
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    const Od8SetEntry& t = in.e[od8CurveTempId(k)];
    const Od8SetEntry& s = in.e[od8CurveSpeedId(k)];
    reset = reset && t.requested == 1 && t.reset == 1 && s.requested == 1 &&
            s.reset == 1 && t.value == first.e[od8CurveTempId(k)].def &&
            s.value == first.e[od8CurveSpeedId(k)].def;
  }
  check(reset, "stock: all ten curve entries requested and reset, at stock");
  check(in.e[15].value == 1 && in.e[15].requested == 1 &&
            in.e[35].value == 30 && in.e[35].requested == 1,
        "stock: zero RPM 1 and its locked stop temperature, both requested");
  check(in.e[0].value == 2354 && in.e[1].value == 500 &&
            in.e[0].requested == 1 && in.e[1].requested == 1 &&
            in.e[0].reset == 0 && in.e[1].reset == 0,
        "stock: the GFX pair as explicit stock values, no reset flags");
  bool others = true;
  const uint32_t untouched[] = {8,  9,  10, 11, 12, 13, 14,
                                16, 17, 18, 29, 36, 37};
  for (uint32_t i : untouched)
    others = others && in.e[i].requested == 0 && in.e[i].reset == 0;
  check(others, "memory, power %, voltage, power mode, auto OC/UV: untouched");
  Od8InitialOut woke = first;
  woke.e[0].def = 2359;
  od8Build(stock, first, woke, &in);
  check(in.e[0].value == 2354,
        "after a wake moved the default to 2359: GFX goes back to 2354, never "
        "above the first read");
  woke.e[0].def = 2340;
  od8Build(stock, first, woke, &in);
  check(in.e[0].value == 2340, "a lower fresh default is used as it is");
  Od8InitialOut defMoved = first;
  defMoved.e[od8CurveTempId(2)].def += 1;
  defMoved.e[od8CurveSpeedId(4)].def -= 2;
  od8Build(stock, first, defMoved, &in);
  check(
      in.e[od8CurveTempId(2)].value == defMoved.e[od8CurveTempId(2)].def &&
          in.e[od8CurveSpeedId(4)].value ==
              defMoved.e[od8CurveSpeedId(4)].def &&
          in.e[od8CurveTempId(2)].reset == 1 && od8ShapeOk(in),
      "the reset carries the fresh curve defaults (what the driver resets to)");

  // Curves.
  const int32_t T[5] = {30, 38, 43, 46, 48};
  const int32_t S[5] = {25, 50, 70, 85, 100};
  Od8Want w = curveWant(T, S);
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::Ok,
        "a curve above stock, 100 % by 48 C: ok");
  const int32_t T50[5] = {30, 40, 45, 48, 50};
  w = curveWant(T50, S);
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::CurveLast,
        "100 % only at 50 C: refused (70 C target - 22 C measured gap)");
  w = curveWant(T, S);
  od8Build(w, first, fresh, &in);
  check(od8ShapeOk(in) && in.e[19].value == 30 && in.e[20].value == 25 &&
            in.e[28].value == 100 && in.e[28].reset == 0 &&
            in.e[19].requested == 1,
        "the curve call carries the ten values, requested, no reset");
  w.speed[0] = 15;
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::CurveRange,
        "a speed under the driver's 20 % minimum: refused");
  w = curveWant(T, S);
  w.temp[2] = 38;
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::CurveOrder,
        "two points at the same temperature: refused");
  w = curveWant(T, S);
  w.speed[3] = 60;
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::CurveOrder,
        "a speed lower than the point before: refused");
  const int32_t Tf[5] = {35, 38, 43, 46, 48};
  w = curveWant(Tf, S);
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::CurveFirst,
        "a first point above 30 C: refused");
  const int32_t Sl[5] = {25, 50, 70, 85, 95};
  w = curveWant(T, Sl);
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::CurveLast,
        "the last point not 100 %: refused");
  const int32_t Th[5] = {30, 40, 45, 48, 55};
  w = curveWant(Th, S);
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::CurveLast,
        "100 % only at 55 C, above 70 - 22 = 48: refused");
  const int32_t Ts[5] = {25, 30, 40, 45, 48};
  const int32_t Ss[5] = {20, 20, 25, 40, 100};
  w = curveWant(Ts, Ss);
  check(od8CheckWant(w, first, fresh, cur) == Od8Check::CurveCooling,
        "20 % at 30 C but only 25 % at 40 C (stock 28 %): less air, refused");
  check(od8StockCurveAt(first, 40) == 28 && od8StockCurveAt(first, 20) == 20 &&
            od8StockCurveAt(first, 80) == 100 &&
            od8StockCurveAt(first, 53) == 44,
        "the stock curve between its points, rounded up (40 C 28 %, 53 C "
        "44 %)");
  w = curveWant(T, S);
  check(od8WantCurveAt(w, 35) == 40 && od8WantCurveAt(w, 20) == 25 &&
            od8WantCurveAt(w, 60) == 100,
        "a requested curve between its points, rounded down");

  // Zero RPM and GFX.
  Od8Want z{};
  z.zeroRpmOff = true;
  check(od8CheckWant(z, first, fresh, cur) == Od8Check::Ok, "zero RPM off: ok");
  od8Build(z, first, fresh, &in);
  check(in.e[15].value == 0 && in.e[15].requested == 1 && od8ShapeOk(in) &&
            in.e[19].reset == 1,
        "zero RPM off: entry 15 = 0, the curve still sent as the reset");
  Od8Want g{};
  g.gfxMaxMHz = 2300;
  check(od8CheckWant(g, first, fresh, cur) == Od8Check::Ok, "GFX max 2300: ok");
  g.gfxMaxMHz = 2400;
  check(od8CheckWant(g, first, fresh, cur) == Od8Check::GfxRange,
        "GFX max above stock: refused");
  g.gfxMaxMHz = 1400;
  check(od8CheckWant(g, first, fresh, cur) == Od8Check::GfxRange,
        "GFX max below 1500: refused");
  g.gfxMaxMHz = 2356;
  check(od8CheckWant(g, first, woke = first, cur) == Od8Check::GfxRange,
        "GFX max 2 MHz above the first stock: refused");

  // The state of the card before any change.
  Od8InitialOut moved = first;
  moved.e[0].def = 2359;
  check(od8CheckWant(stock, first, moved, cur) == Od8Check::Ok,
        "GFX default 5 MHz off after a wake: within the allowance");
  moved.e[0].def = 2400;
  check(od8CheckWant(stock, first, moved, cur) == Od8Check::Drifted,
        "GFX default 46 MHz off: drifted, refused");
  moved = first;
  moved.e[12].def = 75;
  check(od8CheckWant(stock, first, moved, cur) == Od8Check::Drifted,
        "the target temperature changed: refused");
  moved = first;
  moved.e[20].max = 90;
  check(od8CheckWant(stock, first, moved, cur) == Od8Check::Drifted &&
            !od8SameLayout(first, moved),
        "a range changed: refused, and the way back's layout check fails too");
  Od8CurrentOut mem = cur;
  mem.cur[8] = 2100;
  check(od8CheckWant(stock, first, fresh, mem) == Od8Check::MemoryMoved,
        "memory not at stock: refused (the commit would blank the display)");
  Od8InitialOut nz = first;
  nz.e[15].def = 0;
  check(od8CheckWant(z, nz, nz, cur) == Od8Check::NoFeature,
        "zero RPM not on at stock: not offered");
  Od8InitialOut nc = first;
  nc.e[23].feature = 0;
  check(od8CheckWant(stock, nc, nc, cur) == Od8Check::NoFeature,
        "a curve entry not offered: refused");

  // The shape check where the bytes are made.
  od8Build(stock, first, fresh, &in);
  Od8SetIn bad = in;
  bad.e[28].requested = 0;
  check(!od8ShapeOk(bad), "nine curve entries requested: never sent");
  bad = in;
  for (uint32_t i = 19; i <= 27; i++) bad.e[i].requested = 0;
  check(!od8ShapeOk(bad), "only entry 28 requested (the legacy branch): never");
  bad = in;
  bad.e[9].requested = 1;
  check(!od8ShapeOk(bad), "power percent requested: never sent");
  bad = in;
  bad.e[0].reset = 1;
  check(!od8ShapeOk(bad), "a GFX reset flag: never sent");
  bad = in;
  bad.e[0].value = 1000;
  check(!od8ShapeOk(bad), "GFX max under 1500 in the bytes: never sent");
  bad = in;
  bad.count = 37;
  check(!od8ShapeOk(bad), "another count: never sent");
  bad = in;
  bad.header.reserved0 = 0;
  check(!od8ShapeOk(bad), "without the no-replay flag: never sent");

  // The read-back.
  od8Build(z, first, fresh, &in);
  Od8CurrentOut after = cur;
  after.cur[15] = 0;
  check(od8VerifyAfter(in, cur, after) == 0, "read back as sent: ok");
  after.cur[15] = 1;
  check(od8VerifyAfter(in, cur, after) == 16,
        "zero RPM still on after the call: entry 15 reported");
  after = cur;
  after.cur[15] = 0;
  after.cur[9] = 3;
  check(od8VerifyAfter(in, cur, after) == 10,
        "an entry not requested moved: reported");
  after = cur;
  after.cur[15] = 0;
  after.notAllowed = 0;
  check(od8VerifyAfter(in, cur, after) == 39, "the allowed mask moved: 39");
  od8Build(g = Od8Want{0, {}, {}, false, 2300}, first, fresh, &in);
  after = cur;
  after.cur[0] = 2295;
  check(od8VerifyAfter(in, cur, after) == 0, "GFX read back 5 MHz lower: ok");
  after.cur[0] = 2301;
  check(od8VerifyAfter(in, cur, after) == 1, "GFX read back higher: reported");
  od8Build(curveWant(T, S), first, fresh, &in);
  after = cur;  // a rejected curve reads back as the old points
  check(od8VerifyAfter(in, cur, after) == 21,
        "a curve the driver rejected (old points still there): reported");

  // The watchdog.
  Od8Watch dog;
  check(od8Watchdog(&dog, true, 900, 70, 60, 70, 1000) == Od8Dog::Fine,
        "70 C hotspot, fan 60 %: fine");
  check(od8Watchdog(&dog, true, 900, 75, 89, 70, 2000) == Od8Dog::Fine &&
            od8Watchdog(&dog, true, 900, 76, 89, 70, 6000) == Od8Dog::Fine &&
            od8Watchdog(&dog, true, 900, 76, 89, 70, 7000) == Od8Dog::Trip,
        "75 C or more with the fan under 90 % for 5 s: trip");
  Od8Watch full;
  check(od8Watchdog(&full, true, 900, 80, 97, 70, 1000) == Od8Dog::Fine &&
            od8Watchdog(&full, true, 900, 80, 97, 70, 9000) == Od8Dog::Fine,
        "80 C with the fan at 97 % (full PWM reading under 100): fine");
  check(od8DogCanWatch(true, 0) && od8DogCanWatch(true, 2000) &&
            !od8DogCanWatch(true, 2001) && !od8DogCanWatch(false, 0),
        "a curve only with a PMLog copy at most 2 s old");
  dog = Od8Watch{};
  check(od8Watchdog(&dog, true, 900, 78, 90, 70, 1000) == Od8Dog::Fine &&
            od8Watchdog(&dog, true, 900, 74, 90, 70, 3000) == Od8Dog::Fine &&
            od8Watchdog(&dog, true, 900, 78, 90, 70, 5000) == Od8Dog::Fine &&
            od8Watchdog(&dog, true, 900, 78, 90, 70, 9000) == Od8Dog::Fine,
        "the 5 s start again after it cooled under 75 C");
  check(od8Watchdog(&dog, true, 900, 80, 100, 70, 20000) == Od8Dog::Fine,
        "80 C with the fan at 100 %: fine");
  check(od8Watchdog(&dog, true, 900, 91, 97, 70, 20500) == Od8Dog::Fine &&
            od8Watchdog(&dog, true, 900, 94, 100, 70, 20800) == Od8Dog::Fine,
        "91 C at 97 % (what stock reaches after 5 minutes at 240 W): fine");
  check(od8Watchdog(&dog, true, 900, 95, 100, 70, 21000) == Od8Dog::Trip,
        "95 C at any fan speed: trip");
  check(od8Watchdog(&dog, true, 11000, 50, 30, 70, 22000) == Od8Dog::Blind &&
            od8Watchdog(&dog, false, 0, 0, 0, 70, 22000) == Od8Dog::Blind,
        "no reading for 10 s, or none at all: blind (the kext goes back)");

  bool texts = true;
  for (uint32_t c = 0; c <= static_cast<uint32_t>(Od8Check::NoReadings); c++)
    texts = texts && od8CheckText(c)[0] != '\0';
  check(texts && od8CheckText(99)[0] != '\0', "every OD8 refusal has a text");
}

// ----------------------------------------------------------- 0.8.0 tests --
// setOd8's 13 scalars: version, flags, t1..t5, s1..s5, gfxMaxMHz.
static void od8Scalars(uint64_t in[kOd8WireCount], uint64_t flags,
                       const uint64_t t[5], const uint64_t sp[5],
                       uint64_t gfx) {
  in[0] = kChannelVersion;
  in[1] = flags;
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    in[2 + k] = t[k];
    in[7 + k] = sp[k];
  }
  in[12] = gfx;
}
static void readOnlyCard() {
  check(deviceReadable(0x1002, 0x73BF, 0xC0) &&
            deviceReadable(0x1002, 0x73BF, 0xC1),
        "the RX 6900 XT (C0) and the RX 6800 XT (C1) are read");
  check(!deviceReadable(0x1002, 0x73BF, 0xC3) &&
            !deviceReadable(0x1002, 0x73AF, 0xC0) &&
            !deviceReadable(0x1002, 0x73FF, 0xC1) &&
            !deviceReadable(0x10DE, 0x73BF, 0xC0),
        "an RX 6800, a 73AF, a Navi 23 and another vendor are not");
  check(deviceAllowed(0x1002, 0x73BF, 0xC1) &&
            !deviceAllowed(0x1002, 0x73BF, 0xC0),
        "only the C1 may write");
  WritePrereqs ro{false, 1, 1, true, true, true, true};
  check(staticRefusal(ro) == WriteOff::ReadOnlyCard,
        "a read-only card with everything else in place: ReadOnlyCard");
  WritePrereqs rw = ro;
  rw.readOnly = false;
  check(staticRefusal(rw) == WriteOff::None, "the same card writable: None");
  WritePrereqs both = ro;
  both.routed = false;
  check(staticRefusal(both) == WriteOff::Routes,
        "another missing prerequisite comes first (no worker, no reads)");
  check(workerStarts(WriteOff::None) && workerStarts(WriteOff::ReadOnlyCard) &&
            !workerStarts(WriteOff::Routes) && !workerStarts(WriteOff::CtlOff),
        "the worker (which reads) starts on a read-only card");
  // The scan: one read-only card is ReadOnlyCard; a C0 next to a C1 is two
  // cards (NotOneCard), never "read only" (F-6).
  check(scanReason(1, 0) == WriteOff::ReadOnlyCard &&
            scanReason(1, 1) == WriteOff::None &&
            scanReason(2, 2) == WriteOff::None &&
            scanReason(0, 0) == WriteOff::None,
        "the scan marks only a lone read-only card");
  check(scanReason(2, 1) == WriteOff::NotOneCard &&
            scanReason(2, 0) == WriteOff::NotOneCard,
        "a read-only card next to another readable card is NotOneCard");
  // The kept reason (F-7): ReadOnlyCard gives way only to what stops the
  // reads too; everything else keeps the first reason.
  check(keptReason(WriteOff::None, WriteOff::ReadOnlyCard) ==
                WriteOff::ReadOnlyCard &&
            keptReason(WriteOff::ReadOnlyCard, WriteOff::Routes) ==
                WriteOff::Routes &&
            keptReason(WriteOff::ReadOnlyCard, WriteOff::Library) ==
                WriteOff::Library &&
            keptReason(WriteOff::ReadOnlyCard, WriteOff::Start) ==
                WriteOff::Start,
        "a read-only card shows a later reason that also stops the reads");
  check(keptReason(WriteOff::ReadOnlyCard, WriteOff::ReadOnlyCard) ==
                WriteOff::ReadOnlyCard &&
            keptReason(WriteOff::ReadOnlyCard, WriteOff::BootImplausible) ==
                WriteOff::ReadOnlyCard &&
            keptReason(WriteOff::Routes, WriteOff::Teardown) ==
                WriteOff::Routes &&
            keptReason(WriteOff::SendFailed, WriteOff::Routes) ==
                WriteOff::SendFailed,
        "otherwise the first reason stays (the reads still run, or it was "
        "not ReadOnlyCard)");
  check(static_cast<uint32_t>(WriteOff::ReadOnlyCard) == 15 &&
            writeOffText(WriteOff::ReadOnlyCard)[0] != '\0',
        "ReadOnlyCard is 15 and has its own text");
  // Owner alone, not turned off: the read-only mark is its own guard.
  Owner o;
  o.markReadOnly();
  check(!o.isOff() && !o.arm() && !o.isArmed(),
        "arm is refused on a read-only card, by the mark alone");
  check(o.change(7, 1000) == Ask::Off && o.wouldChange(7, 1000) == Ask::Off &&
            o.owner() == 0 && !o.isChanged(),
        "no change is taken on a read-only card");
  Owner late;
  late.arm();
  late.markReadOnly();
  check(!late.isArmed() && late.change(7, 1000) == Ask::Off,
        "a mark after arm closes it too");
  check(armCheck(true, o, true, true) == Reply::Off &&
            armCheck(false, o, true, true) == Reply::NotPrivileged,
        "arm by an administrator answers off; anyone else, not privileged");
  check(disarmCheck(true, o, false) == Reply::Off,
        "disarm answers off on a read-only card");
  // set and setOd8 answer off before they look at any value.
  uint32_t w = 77;
  bool off = valueGate(o) == Reply::Off && setWire(o, 230, &w) == Reply::Off &&
             setWire(o, 0, &w) == Reply::Off &&
             setWire(o, UINT64_MAX, &w) == Reply::Off &&
             setWire(o, 0x100000000ULL, &w) == Reply::Off && w == 77;
  check(off, "set answers off for any watts, absurd ones too, untouched");
  uint64_t in[kOd8WireCount];
  const uint64_t bigT[5] = {999, 0, UINT64_MAX, 5, 1};
  const uint64_t bigS[5] = {UINT64_MAX, 201, 0, 7, 0};
  const uint64_t okT[5] = {30, 40, 44, 46, 48};
  const uint64_t okS[5] = {20, 36, 52, 68, 100};
  Od8Want want{};
  od8Scalars(in, UINT64_MAX, bigT, bigS, UINT64_MAX);
  bool od8off = od8Wire(o, in, &want) == Reply::Off;
  od8Scalars(in, kOd8WantCurve, okT, okS, 2300);
  od8off = od8off && od8Wire(o, in, &want) == Reply::Off;
  od8Scalars(in, 0, okT, okS, 0);
  od8off = od8off && od8Wire(o, in, &want) == Reply::Off;
  check(od8off, "setOd8 answers off for absurd, good and stock states alike");
}
static void disarming() {
  Owner o;
  check(disarmCheck(true, o, false) == Reply::Ok && o.disarm() && !o.isArmed(),
        "disarm of a control never armed is fine (it stays closed)");
  check(o.arm() && o.isArmed(), "arm opens it");
  check(disarmCheck(false, o, false) == Reply::Ok && o.disarm() && !o.isArmed(),
        "a program that is not an administrator closes it while nothing is "
        "applied (owner's decision 2026-11-20)");
  check(armCheck(false, o, true, true) == Reply::NotPrivileged && !o.isArmed(),
        "opening it again still needs an administrator");
  check(o.arm() && disarmCheck(true, o, false) == Reply::Ok && o.disarm() &&
            !o.isArmed(),
        "an administrator closes it too");
  uint32_t w = 77;
  check(o.change(7, 1000) == Ask::NotArmed && valueGate(o) == Reply::NotArmed &&
            setWire(o, 230, &w) == Reply::NotArmed &&
            setWire(o, UINT64_MAX, &w) == Reply::NotArmed && w == 77,
        "after disarm a change is refused as before arm, absurd watts too");
  uint64_t in[kOd8WireCount];
  const uint64_t bigT[5] = {999, 0, 3, 5, 1};
  const uint64_t bigS[5] = {201, 0, 0, 7, 0};
  Od8Want want{};
  od8Scalars(in, 0xff, bigT, bigS, UINT64_MAX);
  check(od8Wire(o, in, &want) == Reply::NotArmed,
        "and setOd8 with an absurd state answers not armed");
  check(o.arm() && o.change(7, 1000) == Ask::Ok,
        "arm opens it again and a change is taken");
  check(disarmCheck(true, o, false) == Reply::StillApplied &&
            disarmCheck(false, o, false) == Reply::StillApplied &&
            !o.disarm() && o.isArmed(),
        "disarm is refused while a program holds a change, for anyone");
  uint64_t id = o.release(7);
  check(id != 0 && disarmCheck(true, o, false) == Reply::StillApplied &&
            !o.disarm(),
        "and while its way back runs");
  o.reverted(id, 2000);
  check(disarmCheck(true, o, false) == Reply::Ok,
        "once the way back is confirmed it can close");
  // The kext's own holds use SetSlot::busy (F-8): a request waiting or
  // running, never an answer that only waits to be collected.
  SetSlot s;
  uint64_t tk = s.post(7, 230);
  bool busyWaiting = s.busy();
  uint64_t t = 0, c = 0;
  uint32_t ww = 0;
  s.take(&t, &c, &ww);
  bool busyRunning = s.busy();
  s.finish(tk, Reply::Ok);
  bool busyDone = s.busy();
  Reply got = Reply::Failed;
  s.collect(tk, &got);
  check(busyWaiting && busyRunning && !busyDone && !s.busy() && s.empty(),
        "a request is being handled while waiting or running, not once "
        "answered");
  check(disarmCheck(true, o, true) == Reply::StillApplied &&
            disarmCheck(false, o, true) == Reply::StillApplied,
        "something the kext still holds (a lower limit, an OD8 state, a "
        "request) refuses it too");
  Owner slept = changedAt(1000);
  slept.willSleep();
  check(slept.owner() == 0 &&
            disarmCheck(false, slept, false) == Reply::StillApplied,
        "a change from before a sleep, not taken back yet, refuses it");
  Owner gone;
  gone.arm();
  gone.turnOff();
  check(disarmCheck(true, gone, false) == Reply::Off && !gone.disarm(),
        "off stays off: disarm answers off");
}
static void wires() {
  Owner o;
  o.arm();
  uint32_t w = 0;
  check(setWire(o, 230, &w) == Reply::Ok && w == 230,
        "armed: set's watts pass to the range check");
  check(setWire(o, 0x100000000ULL, &w) == Reply::AboveBoot,
        "armed: a number that is no watts is above the start-up value");
  check(armCheck(true, Owner{}, false, true) == Reply::NoBootValue &&
            armCheck(true, Owner{}, true, false) == Reply::NotReady &&
            armCheck(true, Owner{}, true, true) == Reply::Ok,
        "arm waits for the start-up limit and the worker");
  Od8InitialOut first;
  cardInitial(&first);
  Od8CurrentOut cur;
  cardCurrent(first, &cur);
  uint64_t in[kOd8WireCount];
  const uint64_t zero[5] = {0, 0, 0, 0, 0};
  const uint64_t okT[5] = {30, 40, 44, 46, 48};
  const uint64_t okS[5] = {20, 36, 52, 68, 100};
  Od8Want want{};
  od8Scalars(in, 4, zero, zero, 0);
  bool bad = od8Wire(o, in, &want) == Reply::BadArgs;
  od8Scalars(in, kOd8WantCurve, okT, okS, 0);
  in[3] = 201;
  bad = bad && od8Wire(o, in, &want) == Reply::BadArgs;
  od8Scalars(in, 0, okT, okS, 0);
  bad = bad && od8Wire(o, in, &want) == Reply::BadArgs;
  od8Scalars(in, 0, zero, zero, 0x80000000ULL);
  bad = bad && od8Wire(o, in, &want) == Reply::BadArgs;
  od8Scalars(in, 0, zero, zero, 0x100000000ULL);
  bad = bad && od8Wire(o, in, &want) == Reply::BadArgs;
  check(bad,
        "armed: unknown flags, a point over 200, points without a curve, a "
        "clock the 32-bit field cannot carry (also 2^32, never read as stock)"
        " are malformed");
  od8Scalars(in, kOd8WantCurve | kOd8WantZeroRpmOff, okT, okS, 2300);
  check(od8Wire(o, in, &want) == Reply::Ok && want.curve && want.zeroRpmOff &&
            want.gfxMaxMHz == 2300 && want.temp[4] == 48 &&
            want.speed[4] == 100,
        "armed: a good state is decoded as sent");
  // S-8: the clock's first check is the card's stock maximum (2354 here).
  od8Scalars(in, 0, zero, zero, 5001);
  check(od8Wire(o, in, &want) == Reply::Ok && want.gfxMaxMHz == 5001 &&
            od8CheckWant(want, first, first, cur) == Od8Check::GfxRange,
        "5001 MHz is no longer cut at the wire: the card's maximum refuses it");
  od8Scalars(in, 0, zero, zero, 2355);
  check(od8Wire(o, in, &want) == Reply::Ok &&
            od8CheckWant(want, first, first, cur) == Od8Check::GfxRange,
        "1 MHz above the stock maximum is refused");
  od8Scalars(in, 0, zero, zero, 2354);
  check(od8Wire(o, in, &want) == Reply::Ok &&
            od8CheckWant(want, first, first, cur) == Od8Check::Ok,
        "the stock maximum itself is taken");
}
// The floor from the card's own table (S-2): the 0x9f of 2026-11-19.
static void floors() {
  Od8InitialOut t;
  cardInitial(&t);
  PowerRange r = powerRange(240, true, false, t);
  check(r.state == FloorState::Known && r.floorW == 225 && r.maxW == 240 &&
            r.percentMin == -6 && r.percentMax == 9,
        "the owner's card: 240 W less 6 % is a 225 W floor (Linux's "
        "power1_cap_min), up to 240");
  check(checkPower(240, r.floorW, 230) == PowerCheck::Ok &&
            checkPower(240, r.floorW, 220) == PowerCheck::BelowFloor &&
            checkPower(240, r.floorW, 200) == PowerCheck::BelowFloor,
        "so 230 W is taken and 220 or 200 W is not");
  check(powerRange(264, true, false, t).floorW == 248,
        "a stock 264 W table: 248 W (264 * 94 / 100, rounded down like "
        "Linux)");
  check(powerRange(255, true, false, t).floorW == 239 &&
            checkPower(255, 239, 240) == PowerCheck::Ok,
        "239.7 W is 239 W, as Linux takes it");
  PowerRange none = powerRange(0, true, false, t);
  check(none.state == FloorState::NoBootValue && none.floorW == 0 &&
            none.maxW == 0,
        "no start-up limit: no floor");
  check(powerRange(301, true, false, t).floorW == 0,
        "an unbelievable start-up limit: no floor");
  PowerRange unread = powerRange(240, false, false, Od8InitialOut{});
  check(unread.state == FloorState::NotRead && unread.floorW == 0 &&
            unread.maxW == 240 &&
            checkPower(240, unread.floorW, 230) == PowerCheck::NoFloor,
        "OD8 not read yet: no floor, every change refused (NoFloor)");
  check(powerRange(240, true, true, t).state == FloorState::NotAsExpected &&
            powerRange(240, true, true, t).floorW == 0,
        "a first 0x9f that was odd gives no floor");
  Od8InitialOut x = t;
  x.e[kOd8PowerPercent].feature = 0x4;
  bool odd = powerRange(240, true, false, x).floorW == 0;
  x = t;
  x.e[kOd8PowerPercent].min = 3;
  odd = odd && powerRange(240, true, false, x).floorW == 0;
  x = t;
  x.e[kOd8PowerPercent].min = -51;
  odd = odd && powerRange(240, true, false, x).floorW == 0;
  x = t;
  x.e[kOd8PowerPercent].min = -6;
  x.e[kOd8PowerPercent].max = -10;
  odd = odd && powerRange(240, true, false, x).floorW == 0;
  x = t;
  x.e[kOd8PowerPercent].zero1 = 1;
  odd = odd && powerRange(240, true, false, x).floorW == 0;
  check(odd,
        "a power entry with another feature bit, a positive or unbelievable "
        "lower bound, min above max or stray words gives no floor");
  x = t;
  x.e[kOd8PowerPercent].min = -50;
  check(powerRange(240, true, false, x).floorW == 120,
        "50 % down is still believed");
  x = t;
  x.e[kOd8PowerPercent].min = 0;
  check(powerRange(240, true, false, x).floorW == 240,
        "0 % down: nothing lower than the start-up limit");
  x = t;
  x.e[kOd8PowerPercent] = Od8Entry{0, -6, 9, 0, 0, 0};
  PowerRange notOffered = powerRange(240, true, false, x);
  check(notOffered.state == FloorState::NotOffered &&
            notOffered.floorW == 240 &&
            checkPower(240, notOffered.floorW, 230) == PowerCheck::BelowFloor,
        "no power limit feature: the floor is the start-up limit (Linux: "
        "od_percent_lower 0)");
  bool texts = true;
  for (uint32_t f = 0; f <= static_cast<uint32_t>(FloorState::NotOffered); f++)
    texts = texts && floorStateText(static_cast<FloorState>(f))[0] != '\0';
  check(texts, "every floor state has a text");
  check(static_cast<uint32_t>(Reply::StillApplied) == 19 &&
            static_cast<uint32_t>(Reply::NoFloor) == 20 &&
            replyText(19)[0] != '\0' && replyText(20)[0] != '\0',
        "the two new replies are 19 and 20, with their texts");
}
int main() {
  card();
  profiles();
  power();
  arming();
  silence();
  closing();
  sleeping();
  failing();
  escapes();
  answers();
  routing();
  asking();
  slot();
  retries();
  waking();
  margins();
  prereqs();
  channel();
  od8();
  od8Writes();
  readOnlyCard();
  disarming();
  wires();
  floors();
  if (failures != 0) printf("%d FAILED\n", failures);
  return failures == 0 ? 0 : 1;
}
