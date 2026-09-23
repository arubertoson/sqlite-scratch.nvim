Output docs/demo.gif

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 720
Set TypingSpeed 45ms
Set PlaybackSpeed 1
Set Framerate 30

Type "nvim --clean -u scripts/demo/init.lua"
Enter
Sleep 3s

# Write a useful question about the sample shop database.
Type "i"
Type "SELECT c.name, c.city, COUNT(o.id) AS orders, ROUND(SUM(o.amount), 2) AS spent"
Enter
Type "FROM customers c JOIN orders o ON o.customer_id = c.id"
Enter
Type "GROUP BY c.id ORDER BY spent DESC;"
Escape
Sleep 1s

# Execute while keeping the query in focus.
Space
Type "rr"
Sleep 2s

# Revise the draft to ask a different question.
Type "ggdG"
Type "i"
Type "SELECT product, amount, ordered_at"
Enter
Type "FROM orders WHERE amount >= 20 ORDER BY amount DESC;"
Escape
Sleep 1s
Space
Type "rr"
Sleep 2s

# Navigate back to the prior execution and reveal its exact SQL.
Type "[r"
Sleep 1s
Space
Type "rs"
Sleep 2s

Type ":qa!"
Enter
Sleep 1s
