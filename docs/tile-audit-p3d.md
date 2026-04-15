# Playful 3D Tile Quality Audit

**Progress:** 473/476 (+ 3 missing)

Comparing Playful 3D tiles against ARASAAC baselines for the Blaster vocabulary.

## Summary

**Coverage:** 473 of 476 vocab keys scored. 3 keys have no p3d (see *Missing Playful 3D*).

**Overall quality:** The refreshed Playful 3D set is strong. The vast majority of tiles scored 12–15/15, and every concrete-noun category (fruit, veggie, meals, snacks, drinks, places, colors, shapes, body parts, weather) is in excellent shape. The weakest areas are abstract verbs and pronouns — exactly where ARASAAC's conventional AAC iconography (arrows, composite symbols) has the edge.

**Flagged tiles:** 37 of 473 (~7.8%). Breakdown by verdict:
- `replace-with-arasaac` — 18 tiles where ARASAAC beats p3d clearly
- `regenerate-p3d` — 10 tiles where both sets are weak and p3d should be redone
- `arasaac-better-but-both-ok` — 7 minor cases, user's judgment call
- `keep-p3d` — 2 cases where p3d, despite being weak, is better than a broken ARASAAC

**Per-wordClass flag counts** (flagged / total in class):
- people — 4/20 (they, mine, she, boy)
- actions — 13/108 (want, turn, get, close, have, hurt, need, see, stand, wear, guess, lose, try, use — p3d's weakest area; abstract verbs hard to render literally)
- social — 6/36 (excuse_me, maybe, whats_up, nice_to_meet, youre_welcome, plus missing how_are_you / i_love_it)
- places — 3/36 (mall, restaurant, pool)
- drinks — 1/11 (iced_tea)
- meals — 1/20 (toast)
- fruit — 1/9 (orange — pale/peach-toned render)
- describe — 6/114 (ugly, hard_, dumb, better, worse, low)
- colors — 1/15 (black)
- describe-position — 1 (around)

**Patterns observed:**
1. **Pronouns** (they, she, mine) — p3d shows generic figures; ARASAAC's arrow-based "pointing-at" convention is clearer.
2. **Abstract verbs** (want, need, use, have, get, try, guess) — neither set does these well; the p3d approach of drawing a kid doing *something* often doesn't communicate the specific verb.
3. **Homonyms/wrong senses** — `pool` (billiards vs swimming), `low` (cow-moo vs height), `hard_` (difficult vs firm), `try` (legal trial vs attempt). These need careful prompts.
4. **Color saturation** — the p3d `orange` fruit is so pale it reads as "peach"; the `black` sphere is half-shaded so it reads as grey/duo-tone.
5. **Similar concepts rendered identically** — `smelly`/`stinky`, `happy`/`funny`, `great`/`awesome`, `light`/`light_`, `hello`/`whats_up`/`goodbye` are nearly interchangeable in p3d. Not flagged individually but worth noting for a future pass.

**Recommendation:** the 18 `replace-with-arasaac` swaps and 10 `regenerate-p3d` prompts together would bring coverage from ~92% usable to ~98%.


## Flagged Tiles

| Key | wordClass | p3d (clarity/match/size = total) | ARASAAC (clarity/match/size = total) | Verdict | Rationale |
|-----|-----------|----------------------------------|--------------------------------------|---------|-----------|
| they | people | 3/4/3 = 10 | 4/4/4 = 12 | replace-with-arasaac | ARASAAC uses arrows to distinguish pronoun from generic group |
| mine | people | 3/3/4 = 10 | 3/4/4 = 11 | arasaac-better-but-both-ok | Both abstract; p3d reads as "hugging teddy" not possession |
| she | people | 3/3/4 = 10 | 4/5/4 = 13 | replace-with-arasaac | ARASAAC arrow makes pronoun clear; p3d reads as generic "girl" |
| boy | people | 3/3/4 = 10 | 5/5/5 = 15 | replace-with-arasaac | p3d gender-ambiguous; ARASAAC unambiguous |
| want | actions | 3/4/3 = 10 | 4/4/4 = 12 | replace-with-arasaac | ARASAAC reach-for-ball clearer than p3d small magical sparkles |
| turn | actions | 3/3/3 = 9 | 4/4/3 = 11 | replace-with-arasaac | p3d reads as "hugging self"; ARASAAC has directional arrow |
| get | actions | 3/3/4 = 10 | 3/4/4 = 11 | arasaac-better-but-both-ok | Both read as "ball"; arasaac marginally more action-like |
| close | actions | 3/3/3 = 9 | 2/2/3 = 7 | regenerate-p3d | p3d reads as "door"; ARASAAC abstract/unusable |
| have | actions | 3/3/4 = 10 | 3/3/4 = 10 | regenerate-p3d | Both weak; "have" is a hard concept to depict |
| hurt | actions | 2/2/4 = 8 | 5/5/4 = 14 | replace-with-arasaac | p3d just shows sad kid; ARASAAC clearly depicts injury |
| need | actions | 3/3/4 = 10 | 3/3/4 = 10 | regenerate-p3d | Both abstract; "need" hard to depict without context |
| see | actions | 3/3/3 = 9 | 4/4/4 = 12 | replace-with-arasaac | p3d shows figure holding eye (odd); ARASAAC clearer |
| stand | actions | 2/3/4 = 9 | 4/5/4 = 13 | replace-with-arasaac | p3d indistinguishable from generic kid |
| wear | actions | 3/3/4 = 10 | 2/2/3 = 7 | regenerate-p3d | p3d just a kid in clothes; ARASAAC wrong/unusable |
| guess | actions | 3/3/4 = 10 | 4/4/3 = 11 | arasaac-better-but-both-ok | p3d indistinguishable from "think"; ARASAAC iconic (wizard) |
| lose | actions | 2/2/3 = 7 | 3/4/3 = 10 | replace-with-arasaac | p3d reads as ghost/spooky; ARASAAC sad-face+question clearer |
| try | actions | 3/3/3 = 9 | 1/1/3 = 5 | regenerate-p3d | p3d ambiguous artistic pose; ARASAAC shows legal trial (wrong sense) |
| use | actions | 2/3/3 = 8 | 3/3/4 = 10 | arasaac-better-but-both-ok | Hard abstract verb; both weak |
| excuse_me | social | 3/3/4 = 10 | 3/3/3 = 9 | keep-p3d | Both weak; p3d slightly preferable |
| maybe | social | 2/2/3 = 7 | 3/4/4 = 11 | replace-with-arasaac | p3d is odd two-headed sculpture; ARASAAC checkboxes clearer |
| whats_up | social | 3/3/4 = 10 | 3/3/4 = 10 | regenerate-p3d | Both weak; whats_up hard to depict without text |
| nice_to_meet | social | 3/4/3 = 10 | 4/4/4 = 12 | replace-with-arasaac | ARASAAC handshake scans better at small size |
| youre_welcome | social | 3/3/3 = 9 | 2/2/3 = 7 | regenerate-p3d | p3d ambiguous; ARASAAC misinterprets as "welcome" (home) |
| mall | places | 3/3/3 = 9 | 4/5/4 = 13 | replace-with-arasaac | p3d just a tall building; ARASAAC clearly depicts shops+parking |
| restaurant | places | 3/3/3 = 9 | 5/5/4 = 14 | replace-with-arasaac | p3d reads as generic storefront; ARASAAC has iconic plate+utensils |
| pool | places | 2/2/4 = 8 | 2/2/4 = 8 | regenerate-p3d | Both depict billiard pool; should be swimming pool for places context |
| iced_tea | drinks | 3/3/3 = 9 | 5/5/4 = 14 | replace-with-arasaac | p3d reads as pitcher/juice; ARASAAC has tea bag + ice visible |
| toast | meals | 3/3/4 = 10 | 3/3/3 = 9 | keep-p3d | Both show "toaster"; p3d marginally cleaner |
| orange | fruit | 3/3/4 = 10 | 5/5/5 = 15 | replace-with-arasaac | p3d orange is pale/peach-colored; ARASAAC vividly orange |
| ugly | describe | 2/3/4 = 9 | 4/4/4 = 12 | replace-with-arasaac | p3d reads as angry/dirty kid; ARASAAC unattractive face clearer |
| hard_ | describe | 2/3/3 = 8 | 2/2/3 = 7 | regenerate-p3d | Both ambiguous; p3d abstract, ARASAAC shows "difficult" (wrong sense) |
| dumb | describe | 3/3/3 = 9 | 3/3/4 = 10 | arasaac-better-but-both-ok | Both weak; word is ambiguous (silly vs mute vs unintelligent) |
| better | describe | 2/3/3 = 8 | 4/4/4 = 12 | replace-with-arasaac | p3d flower is metaphor; ARASAAC growth-bars clearer |
| worse | describe | 3/3/4 = 10 | 4/4/4 = 12 | arasaac-better-but-both-ok | p3d just a down-arrow; ARASAAC thumbs-down marginally more semantic |
| low | describe | 3/3/3 = 9 | 1/1/3 = 5 | regenerate-p3d | p3d reads as "tall shelf"; ARASAAC uses "low" as cow-moo (wrong sense) |
| around | describe | 3/4/3 = 10 | 4/5/4 = 13 | replace-with-arasaac | ARASAAC orbit visualization clearer than p3d flower-in-fence |
| black | colors | 3/3/4 = 10 | 4/5/4 = 13 | replace-with-arasaac | p3d is half-black/half-white sphere (confusing); ARASAAC pure black splotch |

## Missing Playful 3D

- `he` (people) — ARASAAC exists but no p3d
- `how_are_you` (social) — missing from both
- `i_love_it` (social) — missing from both

## Appendix — Full p3d scores

home: 15/15
next_page: 15/15
previous_page: 15/15
food: 13/15
body_health: 11/15
question: 15/15
snack: 12/15
popsicle: 15/15
graham_cracker: 12/15
goldfish_cracker: 15/15
snack_bar: 13/15
pretzel: 15/15
tired: 14/15
happy: 15/15
slide: 12/15
basketball: 15/15
tricycle: 13/15
friend: 13/15
dad: 15/15
family: 14/15
mom: 15/15
brother: 11/15
people: 13/15
sister: 13/15
grandma: 14/15
student: 14/15
they: 10/15
mine: 10/15
grandpa: 15/15
girl: 15/15
she: 10/15
we: 13/15
baby: 15/15
teacher: 14/15
boy: 10/15
school_people: 11/15
actions: 15/15
play: 13/15
read: 15/15
stop: 15/15
want: 10/15
take: 13/15
tell: 14/15
turn: 9/15
watch: 14/15
eat: 15/15
drink: 15/15
finish: 12/15
get: 10/15
come: 12/15
go: 15/15
help: 13/15
open: 13/15
put: 13/15
like: 15/15
answer: 14/15
ask: 15/15
buy: 14/15
call: 15/15
clean: 12/15
cook: 14/15
color: 14/15
close: 9/15
feel: 12/15
give: 13/15
have: 10/15
dance: 14/15
draw: 14/15
drive: 14/15
hurt: 8/15
hear: 14/15
know: 12/15
listen: 12/15
look: 14/15
find: 14/15
jump: 14/15
learn: 14/15
leave: 13/15
love: 15/15
make: 11/15
need: 10/15
line_up: 14/15
pull: 14/15
push: 14/15
remember: 12/15
ride: 14/15
say: 14/15
see: 9/15
show: 12/15
run: 14/15
shop: 14/15
sing: 15/15
sit: 14/15
sleep: 14/15
talk: 14/15
walk: 12/15
think: 14/15
stand: 9/15
swim: 12/15
swing: 13/15
write: 14/15
wash: 14/15
wear: 10/15
work: 12/15
blow: 14/15
blush: 13/15
bowl: 14/15
brush: 14/15
catch: 14/15
chew: 12/15
clap: 14/15
cry: 13/15
dress_up: 12/15
dry: 13/15
email: 14/15
fall: 14/15
fly: 13/15
forget: 14/15
guess: 10/15
hate: 12/15
hope: 12/15
kick: 14/15
kiss: 12/15
live: 12/15
lose: 7/15
meet: 14/15
move: 14/15
nap: 14/15
paint: 11/15
pray: 14/15
smell: 14/15
wait: 11/15
wish: 12/15
brush_teeth: 14/15
speak: 12/15
throw: 14/15
try: 9/15
understand: 14/15
use: 8/15
wash_hair: 14/15
bathe: 14/15
shower: 15/15
wash_hands: 14/15
polish_nails: 14/15
social: 11/15
yes: 15/15
no: 15/15
bathroom: 14/15
sorry: 11/15
excuse_me: 10/15
problem: 12/15
i_dont_know: 14/15
maybe: 7/15
hello: 14/15
whats_up: 10/15
goodbye: 12/15
goodnight: 14/15
nice_to_meet: 10/15
please: 12/15
thank_you: 13/15
youre_welcome: 9/15
okay: 12/15
hungry: 13/15
thirsty: 11/15
sick: 14/15
be_quiet: 14/15
cool: 14/15
great: 14/15
uh_oh: 12/15
no_way: 12/15
i_love_you: 14/15
awesome: 12/15
oh_my: 14/15
funny: 14/15
school: 15/15
places: 15/15
house: 15/15
bedroom: 14/15
closet: 13/15
dining_room: 14/15
kitchen: 14/15
living_room: 14/15
laundry: 14/15
door: 14/15
window: 14/15
building: 15/15
airport: 14/15
bowling_alley: 14/15
church: 15/15
doctor: 15/15
grocery_store: 14/15
mall: 9/15
movie: 14/15
restaurant: 9/15
store: 12/15
outside: 11/15
beach: 14/15
camp: 14/15
farm: 14/15
lake: 14/15
ocean: 14/15
park: 13/15
playground: 14/15
pool: 8/15
zoo: 14/15
class: 14/15
bus: 15/15
library: 14/15
lunch: 14/15
therapy: 11/15
speech: 11/15
drinks: 13/15
juice: 14/15
milk: 14/15
chocolate_milk: 14/15
water: 14/15
soda: 15/15
iced_tea: 9/15
milkshake: 14/15
lemonade: 15/15
ice_cubes: 15/15
snacks: 14/15
crackers: 12/15
cookie: 15/15
fruit_snack: 14/15
pudding: 14/15
applesauce: 14/15
yogurt: 14/15
popcorn: 15/15
pretzels: 15/15
chips: 14/15
meals: 13/15
sandwich: 14/15
macaroni: 14/15
pizza: 15/15
hamburger: 15/15
fries: 15/15
hot_dog: 15/15
nuggets: 14/15
salad: 14/15
soup: 14/15
cereal: 14/15
oatmeal: 11/15
toast: 10/15
eggs: 11/15
pancakes: 14/15
syrup: 14/15
peanut_butter: 13/15
jelly: 14/15
sausage: 13/15
cheese: 15/15
fruit: 14/15
apple: 15/15
banana: 15/15
blueberries: 15/15
orange: 10/15
cherry: 15/15
grapes: 15/15
lemon: 15/15
strawberry: 15/15
pear: 15/15
veggie: 14/15
broccoli: 15/15
carrot: 15/15
corn: 15/15
cucumber: 15/15
green_beans: 15/15
pepper: 15/15
lettuce: 14/15
tomato: 15/15
potato: 15/15
shape: 15/15
circle: 15/15
square: 15/15
heart: 13/15
triangle: 15/15
diamond: 15/15
star: 15/15
rectangle: 15/15
oval: 15/15
octagon: 15/15
art: 14/15
markers: 12/15
crayons: 14/15
pencil: 15/15
paintbrush: 14/15
paints: 14/15
scissors: 15/15
tape: 14/15
glue: 14/15
paper: 13/15
body: 13/15
head: 14/15
eye: 15/15
ear: 15/15
nose: 14/15
mouth: 15/15
arm: 14/15
leg: 13/15
stomach: 13/15
back: 13/15
health: 14/15
cold: 14/15
fever: 14/15
headache: 14/15
sore_throat: 14/15
stomachache: 14/15
toothache: 13/15
toy: 14/15
ipad: 14/15
blocks: 14/15
bubbles: 14/15
cars: 15/15
trampoline: 14/15
puzzle: 14/15
playdoh: 12/15
doll: 13/15
sports: 14/15
baseball: 15/15
bassketball: 14/15
football: 15/15
ball: 15/15
soccer: 15/15
tennis: 14/15
games: 12/15
bingo: 13/15
cards: 14/15
video_game: 14/15
weather: 14/15
cold_: 14/15
hot: 14/15
cool_: 12/15
warm: 13/15
rain: 15/15
cloud: 15/15
sun: 15/15
wind: 14/15
fog: 13/15
rainbow: 14/15
storm: 13/15
lightning: 15/15
thunder: 12/15
tornado: 14/15
snow: 11/15
describe: 12/15
big: 14/15
little: 14/15
clean_: 13/15
dirty: 14/15
sad: 15/15
fine: 12/15
okay_: 14/15
bad: 12/15
good: 12/15
cold__: 14/15
hot_: 14/15
easy: 12/15
hard: 13/15
more: 13/15
fast: 14/15
slow: 15/15
full: 14/15
empty: 14/15
pretty: 12/15
ugly: 9/15
hard_: 8/15
soft: 12/15
busy: 11/15
cute: 14/15
short: 12/15
long: 13/15
loud: 14/15
quiet: 14/15
smart: 12/15
dumb: 9/15
excited: 14/15
nice: 11/15
proud: 13/15
fun: 12/15
new: 13/15
old: 13/15
right: 15/15
wrong: 15/15
angry: 15/15
bored: 14/15
frustrated: 14/15
mean: 12/15
yummy: 13/15
funny_: 14/15
same: 15/15
different: 15/15
wet: 14/15
dry_: 14/15
messy: 14/15
scared: 15/15
stinky: 13/15
uncomfortable: 13/15
yucky: 14/15
better: 8/15
worse: 10/15
excellent: 15/15
terrible: 12/15
heavy: 14/15
light: 15/15
together: 14/15
apart: 14/15
asleep: 15/15
crazy: 12/15
best: 14/15
worst: 13/15
exciting: 12/15
boring: 13/15
high: 14/15
low: 9/15
true: 14/15
false: 15/15
quick: 14/15
silly: 14/15
broken: 14/15
fixed: 13/15
fat: 14/15
thin: 14/15
light_: 12/15
dark: 14/15
young: 12/15
old_: 14/15
surprised: 15/15
terrific: 12/15
cheap: 12/15
expensive: 13/15
few: 12/15
many: 14/15
near: 12/15
far: 14/15
alone: 13/15
lonely: 13/15
afraid: 12/15
smelly: 12/15
there: 12/15
away: 13/15
this: 13/15
again: 15/15
around: 10/15
front: 13/15
back_: 13/15
behind: 13/15
top: 14/15
over: 14/15
under: 14/15
not: 15/15
don't: 15/15
between: 14/15
middle: 14/15
through: 14/15
or: 14/15
bottom: 13/15
left: 15/15
right_: 15/15
red: 15/15
orange_: 15/15
yellow: 15/15
green: 15/15
blue: 15/15
purple: 15/15
pink: 15/15
black: 10/15
brown: 15/15
white: 14/15
grey: 15/15
gold: 15/15
silver: 13/15
tan: 15/15
colors: 15/15
