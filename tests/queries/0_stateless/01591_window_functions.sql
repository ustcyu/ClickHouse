-- { echo }

set allow_experimental_window_functions = 1;

-- just something basic
select number, count() over (partition by intDiv(number, 3) order by number rows unbounded preceding) from numbers(10);

-- proper calculation across blocks
select number, max(number) over (partition by intDiv(number, 3) order by number desc rows unbounded preceding) from numbers(10) settings max_block_size = 2;

-- not a window function
select number, abs(number) over (partition by toString(intDiv(number, 3)) rows unbounded preceding) from numbers(10); -- { serverError 63 }

-- no partition by
select number, avg(number) over (order by number rows unbounded preceding) from numbers(10);

-- no order by
select number, quantileExact(number) over (partition by intDiv(number, 3) rows unbounded preceding) from numbers(10);

-- can add an alias after window spec
select number, quantileExact(number) over (partition by intDiv(number, 3) rows unbounded preceding) q from numbers(10);

-- can't reference it yet -- the window functions are calculated at the
-- last stage of select, after all other functions.
select q * 10, quantileExact(number) over (partition by intDiv(number, 3) rows unbounded preceding) q from numbers(10); -- { serverError 47 }

-- must work in WHERE if you wrap it in a subquery
select * from (select count(*) over (rows unbounded preceding) c from numbers(3)) where c > 0;

-- should work in ORDER BY
select number, max(number) over (partition by intDiv(number, 3) order by number desc rows unbounded preceding) m from numbers(10) order by m desc, number;

-- also works in ORDER BY if you wrap it in a subquery
select * from (select count(*) over (rows unbounded preceding) c from numbers(3)) order by c;

-- Example with window function only in ORDER BY. Here we make a rank of all
-- numbers sorted descending, and then sort by this rank descending, and must get
-- the ascending order.
select * from (select * from numbers(5) order by rand()) order by count() over (order by number desc rows unbounded preceding) desc;

-- Aggregate functions as window function arguments. This query is semantically
-- the same as the above one, only we replace `number` with
-- `any(number) group by number` and so on.
select * from (select * from numbers(5) order by rand()) group by number order by sum(any(number + 1)) over (order by min(number) desc rows unbounded preceding) desc;
-- some more simple cases w/aggregate functions
select sum(any(number)) over (rows unbounded preceding) from numbers(1);
select sum(any(number) + 1) over (rows unbounded preceding) from numbers(1);
select sum(any(number + 1)) over (rows unbounded preceding) from numbers(1);

-- different windows
-- an explain test would also be helpful, but it's too immature now and I don't
-- want to change reference all the time
select number, max(number) over (partition by intDiv(number, 3) order by number desc rows unbounded preceding), count(number) over (partition by intDiv(number, 5) order by number rows unbounded preceding) as m from numbers(31) order by number settings max_block_size = 2;

-- two functions over the same window
-- an explain test would also be helpful, but it's too immature now and I don't
-- want to change reference all the time
select number, max(number) over (partition by intDiv(number, 3) order by number desc rows unbounded preceding), count(number) over (partition by intDiv(number, 3) order by number desc rows unbounded preceding) as m from numbers(7) order by number settings max_block_size = 2;

-- check that we can work with constant columns
select median(x) over (partition by x) from (select 1 x);

-- an empty window definition is valid as well
select groupArray(number) over (rows unbounded preceding) from numbers(3);
select groupArray(number) over () from numbers(3);

-- This one tests we properly process the window  function arguments.
-- Seen errors like 'column `1` not found' from count(1).
select count(1) over (rows unbounded preceding), max(number + 1) over () from numbers(3);

-- Should work in DISTINCT
select distinct sum(0) over (rows unbounded preceding) from numbers(2);
select distinct any(number) over (rows unbounded preceding) from numbers(2);

-- Various kinds of aliases are properly substituted into various parts of window
-- function definition.
with number + 1 as x select intDiv(number, 3) as y, sum(x + y) over (partition by y order by x rows unbounded preceding) from numbers(7);

-- WINDOW clause
select 1 window w1 as ();

select sum(number) over w1, sum(number) over w2
from numbers(10)
window
    w1 as (rows unbounded preceding),
    w2 as (partition by intDiv(number, 3) rows unbounded preceding)
;

-- FIXME both functions should use the same window, but they don't. Add an
-- EXPLAIN test for this.
select
    sum(number) over w1,
    sum(number) over (partition by intDiv(number, 3) rows unbounded preceding)
from numbers(10)
window
    w1 as (partition by intDiv(number, 3) rows unbounded preceding)
;

-- RANGE frame
-- It's the default
select sum(number) over () from numbers(3);

-- Try some mutually prime sizes of partition, group and block, for the number
-- of rows that is their least common multiple + 1, so that we see all the
-- interesting corner cases.
select number, intDiv(number, 3) p, mod(number, 2) o, count(number) over w as c
from numbers(31)
window w as (partition by p order by o range unbounded preceding)
order by number
settings max_block_size = 5
;

select number, intDiv(number, 5) p, mod(number, 3) o, count(number) over w as c
from numbers(31)
window w as (partition by p order by o range unbounded preceding)
order by number
settings max_block_size = 2
;

select number, intDiv(number, 5) p, mod(number, 2) o, count(number) over w as c
from numbers(31)
window w as (partition by p order by o range unbounded preceding)
order by number
settings max_block_size = 3
;

select number, intDiv(number, 3) p, mod(number, 5) o, count(number) over w as c
from numbers(31)
window w as (partition by p order by o range unbounded preceding)
order by number
settings max_block_size = 2
;

select number, intDiv(number, 2) p, mod(number, 5) o, count(number) over w as c
from numbers(31)
window w as (partition by p order by o range unbounded preceding)
order by number
settings max_block_size = 3
;

select number, intDiv(number, 2) p, mod(number, 3) o, count(number) over w as c
from numbers(31)
window w as (partition by p order by o range unbounded preceding)
order by number
settings max_block_size = 5
;

-- A case where the partition end is in the current block, and the frame end
-- is triggered by the partition end.
select min(number) over (partition by p)  from (select number, intDiv(number, 3) p from numbers(10));

-- UNBOUNDED FOLLOWING frame end
select
    min(number) over wa, min(number) over wo,
    max(number) over wa, max(number) over wo
from
    (select number, intDiv(number, 3) p, mod(number, 5) o
        from numbers(31))
window
    wa as (partition by p order by o
        range between unbounded preceding and unbounded following),
    wo as (partition by p order by o
        rows between unbounded preceding and unbounded following)
settings max_block_size = 2;

