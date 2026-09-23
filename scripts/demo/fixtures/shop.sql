CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    city TEXT NOT NULL
);

CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    product TEXT NOT NULL,
    amount REAL NOT NULL,
    ordered_at TEXT NOT NULL
);

INSERT INTO customers (name, city) VALUES
    ('Ada Lovelace', 'London'),
    ('Grace Hopper', 'Arlington'),
    ('Katherine Johnson', 'White Sulphur Springs'),
    ('Edsger Dijkstra', 'Nuenen');

INSERT INTO orders (customer_id, product, amount, ordered_at) VALUES
    (1, 'Analytical Engine notebook', 24.50, '2025-02-03'),
    (1, 'Brass compass', 18.00, '2025-02-11'),
    (2, 'Compiler field guide', 32.00, '2025-02-08'),
    (3, 'Orbital calculator', 45.00, '2025-02-14'),
    (4, 'Graph paper set', 9.50, '2025-02-18');
