-- 1. Create and select the database
CREATE DATABASE personal_finance;
USE personal_finance;

-- 2. Set strict SQL mode for data integrity
SET SQL_MODE = 'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO';

-- 3. Create users table
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    full_name VARCHAR(100) NOT NULL,
    registration_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_email CHECK (email LIKE '%@%.%')
) COMMENT 'Stores user account information';

-- 4. Create categories table
CREATE TABLE categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    name VARCHAR(50) NOT NULL,
    description VARCHAR(255),
    type ENUM('income', 'expense') NOT NULL,
    parent_category_id INT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_category_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_parent_category FOREIGN KEY (parent_category_id) REFERENCES categories(category_id),
    CONSTRAINT uc_user_category UNIQUE (user_id, name, type)
) COMMENT 'Stores custom categories for income and expenses, with optional hierarchy';

-- 5. Create transactions table
CREATE TABLE transactions (
    transaction_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    category_id INT NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    transaction_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description VARCHAR(255),
    type ENUM('income', 'expense') NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_transaction_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_transaction_category FOREIGN KEY (category_id) REFERENCES categories(category_id),
    CONSTRAINT chk_amount_positive CHECK (amount > 0)
) COMMENT 'Records all financial transactions with category associations';

-- 6. Create audit log table
CREATE TABLE transaction_audit_log (
    audit_id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id INT NOT NULL,
    user_id INT NOT NULL,
    action_type ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    old_amount DECIMAL(12, 2),
    new_amount DECIMAL(12, 2),
    old_category_id INT,
    new_category_id INT,
    action_timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(100) NOT NULL DEFAULT 'system',
    CONSTRAINT fk_audit_transaction FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id) ON DELETE CASCADE,
    CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(user_id)
) COMMENT 'Tracks all changes made to transactions for audit purposes';

-- 7. Create triggers to prevent category self-reference
DELIMITER //
CREATE TRIGGER prevent_self_reference_categories_insert
BEFORE INSERT ON categories
FOR EACH ROW
BEGIN
    IF NEW.parent_category_id = NEW.category_id THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'A category cannot be its own parent';
    END IF;
END//
DELIMITER ;

DELIMITER //
CREATE TRIGGER prevent_self_reference_categories_update
BEFORE UPDATE ON categories
FOR EACH ROW
BEGIN
    IF NEW.parent_category_id = NEW.category_id THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'A category cannot be its own parent';
    END IF;
END//
DELIMITER ;

-- 8. Create trigger to validate transaction type matches category type
DELIMITER //
CREATE TRIGGER validate_transaction_category
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE category_type VARCHAR(10);
    
    SELECT type INTO category_type FROM categories WHERE category_id = NEW.category_id;
    
    IF category_type != NEW.type THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Transaction type must match category type';
    END IF;
END//
DELIMITER ;

-- 9. Create audit triggers for transactions
DELIMITER //
CREATE TRIGGER log_transaction_insert
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    INSERT INTO transaction_audit_log (
        transaction_id,
        user_id,
        action_type,
        new_amount,
        new_category_id,
        changed_by
    ) VALUES (
        NEW.transaction_id,
        NEW.user_id,
        'INSERT',
        NEW.amount,
        NEW.category_id,
        USER()
    );
END//
DELIMITER ;

DELIMITER //
CREATE TRIGGER log_transaction_update
AFTER UPDATE ON transactions
FOR EACH ROW
BEGIN
    INSERT INTO transaction_audit_log (
        transaction_id,
        user_id,
        action_type,
        old_amount,
        new_amount,
        old_category_id,
        new_category_id,
        changed_by
    ) VALUES (
        NEW.transaction_id,
        NEW.user_id,
        'UPDATE',
        OLD.amount,
        NEW.amount,
        OLD.category_id,
        NEW.category_id,
        USER()
    );
END//
DELIMITER ;

DELIMITER //
CREATE TRIGGER log_transaction_delete
AFTER DELETE ON transactions
FOR EACH ROW
BEGIN
    INSERT INTO transaction_audit_log (
        transaction_id,
        user_id,
        action_type,
        old_amount,
        old_category_id,
        changed_by
    ) VALUES (
        OLD.transaction_id,
        OLD.user_id,
        'DELETE',
        OLD.amount,
        OLD.category_id,
        USER()
    );
END//
DELIMITER ;

-- 10. Create monthly summary view
CREATE OR REPLACE VIEW monthly_summary AS
SELECT 
    u.user_id,
    u.username,
    YEAR(t.transaction_date) AS year,
    MONTH(t.transaction_date) AS month,
    SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END) AS total_income,
    SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END) AS total_expense,
    SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE -t.amount END) AS net_balance,
    COUNT(DISTINCT CASE WHEN t.type = 'income' THEN t.category_id END) AS income_categories_count,
    COUNT(DISTINCT CASE WHEN t.type = 'expense' THEN t.category_id END) AS expense_categories_count
FROM 
    users u
LEFT JOIN 
    transactions t ON u.user_id = t.user_id
GROUP BY 
    u.user_id, YEAR(t.transaction_date), MONTH(t.transaction_date)
ORDER BY 
    u.user_id, year DESC, month DESC;

-- 11. Create monthly category summary view
CREATE OR REPLACE VIEW monthly_category_summary AS
SELECT 
    u.user_id,
    u.username,
    c.category_id,
    c.name AS category_name,
    c.type AS category_type,
    YEAR(t.transaction_date) AS year,
    MONTH(t.transaction_date) AS month,
    SUM(t.amount) AS total_amount,
    COUNT(*) AS transaction_count
FROM 
    users u
JOIN 
    categories c ON u.user_id = c.user_id
LEFT JOIN 
    transactions t ON c.category_id = t.category_id
GROUP BY 
    u.user_id, c.category_id, YEAR(t.transaction_date), MONTH(t.transaction_date)
ORDER BY 
    u.user_id, category_type, year DESC, month DESC, total_amount DESC;

-- 12. Create user balances view
CREATE OR REPLACE VIEW user_balances AS
SELECT 
    u.user_id,
    u.username,
    u.full_name,
    COALESCE((
        SELECT SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE -t.amount END)
        FROM transactions t
        WHERE t.user_id = u.user_id
    ), 0) AS current_balance,
    (
        SELECT SUM(amount) FROM transactions t 
        WHERE t.user_id = u.user_id AND t.type = 'income'
    ) AS lifetime_income,
    (
        SELECT SUM(amount) FROM transactions t 
        WHERE t.user_id = u.user_id AND t.type = 'expense'
    ) AS lifetime_expense
FROM 
    users u;

-- 13. Create top expense categories view
CREATE OR REPLACE VIEW top_expense_categories AS
SELECT 
    user_id,
    username,
    category_id,
    category_name,
    total_amount,
    category_rank
FROM (
    SELECT 
        u.user_id,
        u.username,
        c.category_id,
        c.name AS category_name,
        SUM(t.amount) AS total_amount,
        RANK() OVER (PARTITION BY u.user_id ORDER BY SUM(t.amount) DESC) AS category_rank
    FROM 
        users u
    JOIN 
        categories c ON u.user_id = c.user_id AND c.type = 'expense'
    LEFT JOIN 
        transactions t ON c.category_id = t.category_id
    GROUP BY 
        u.user_id, c.category_id
) ranked_categories
WHERE 
    category_rank <= 3;

-- 14. Create top income categories view
CREATE OR REPLACE VIEW top_income_categories AS
SELECT 
    user_id,
    username,
    category_id,
    category_name,
    total_amount,
    category_rank
FROM (
    SELECT 
        u.user_id,
        u.username,
        c.category_id,
        c.name AS category_name,
        SUM(t.amount) AS total_amount,
        RANK() OVER (PARTITION BY u.user_id ORDER BY SUM(t.amount) DESC) AS category_rank
    FROM 
        users u
    JOIN 
        categories c ON u.user_id = c.user_id AND c.type = 'income'
    LEFT JOIN 
        transactions t ON c.category_id = t.category_id
    GROUP BY 
        u.user_id, c.category_id
) ranked_categories
WHERE 
    category_rank <= 3;

-- 15. Create category hierarchy view
CREATE OR REPLACE VIEW category_hierarchy AS
SELECT 
    parent.category_id AS parent_category_id,
    parent.name AS parent_category_name,
    parent.type AS parent_category_type,
    child.category_id AS child_category_id,
    child.name AS child_category_name,
    child.user_id,
    u.username
FROM 
    categories parent
RIGHT JOIN 
    categories child ON parent.category_id = child.parent_category_id
JOIN 
    users u ON child.user_id = u.user_id
ORDER BY 
    child.user_id, parent_category_name, child_category_name;
    
-- 16. Create procedure to generate monthly report
DELIMITER //
CREATE PROCEDURE generate_monthly_report(
    IN p_user_id INT,
    IN p_year INT,
    IN p_month INT
)
BEGIN
    -- Validate user exists
    DECLARE user_exists INT;
    SELECT COUNT(*) INTO user_exists FROM users WHERE user_id = p_user_id;
    
    IF user_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';
    END IF;
    
    -- Report header
    SELECT 
        u.username,
        u.full_name,
        p_year AS report_year,
        p_month AS report_month,
        COALESCE(ms.total_income, 0) AS total_income,
        COALESCE(ms.total_expense, 0) AS total_expense,
        COALESCE(ms.net_balance, 0) AS net_balance
    FROM 
        users u
    LEFT JOIN 
        monthly_summary ms ON u.user_id = ms.user_id 
        AND ms.year = p_year 
        AND ms.month = p_month
    WHERE 
        u.user_id = p_user_id;
    
    -- Income by category
    SELECT 
        c.name AS category_name,
        COALESCE(SUM(t.amount), 0) AS total_amount,
        COUNT(*) AS transaction_count
    FROM 
        categories c
    LEFT JOIN 
        transactions t ON c.category_id = t.category_id
        AND YEAR(t.transaction_date) = p_year
        AND MONTH(t.transaction_date) = p_month
        AND t.type = 'income'
    WHERE 
        c.user_id = p_user_id
        AND c.type = 'income'
    GROUP BY 
        c.category_id
    ORDER BY 
        total_amount DESC;
    
    -- Expenses by category
    SELECT 
        c.name AS category_name,
        COALESCE(SUM(t.amount), 0) AS total_amount,
        COUNT(*) AS transaction_count
    FROM 
        categories c
    LEFT JOIN 
        transactions t ON c.category_id = t.category_id
        AND YEAR(t.transaction_date) = p_year
        AND MONTH(t.transaction_date) = p_month
        AND t.type = 'expense'
    WHERE 
        c.user_id = p_user_id
        AND c.type = 'expense'
    GROUP BY 
        c.category_id
    ORDER BY 
        total_amount DESC;
    
    -- Top transactions
    SELECT 
        t.transaction_id,
        t.amount,
        t.type,
        t.transaction_date,
        t.description,
        c.name AS category_name
    FROM 
        transactions t
    JOIN 
        categories c ON t.category_id = c.category_id
    WHERE 
        t.user_id = p_user_id
        AND YEAR(t.transaction_date) = p_year
        AND MONTH(t.transaction_date) = p_month
    ORDER BY 
        t.amount DESC
    LIMIT 10;
END //
DELIMITER ;

-- 17. Create procedure to get category totals
DELIMITER //
CREATE PROCEDURE get_category_totals(
    IN p_user_id INT,
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_type ENUM('income', 'expense', 'both')
)
BEGIN
    -- Validate user exists
    DECLARE user_exists INT;
    SELECT COUNT(*) INTO user_exists FROM users WHERE user_id = p_user_id;
    
    IF user_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';
    END IF;
    
    -- Validate date range
    IF p_start_date > p_end_date THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Start date must be before end date';
    END IF;
    
    -- Get category totals based on type filter
    IF p_type = 'both' THEN
        SELECT 
            c.category_id,
            c.name AS category_name,
            c.type AS category_type,
            COALESCE(SUM(t.amount), 0) AS total_amount,
            COUNT(t.transaction_id) AS transaction_count
        FROM 
            categories c
        LEFT JOIN 
            transactions t ON c.category_id = t.category_id
            AND t.transaction_date BETWEEN p_start_date AND p_end_date
        WHERE 
            c.user_id = p_user_id
        GROUP BY 
            c.category_id
        ORDER BY 
            c.type, total_amount DESC;
    ELSE
        SELECT 
            c.category_id,
            c.name AS category_name,
            c.type AS category_type,
            COALESCE(SUM(t.amount), 0) AS total_amount,
            COUNT(t.transaction_id) AS transaction_count
        FROM 
            categories c
        LEFT JOIN 
            transactions t ON c.category_id = t.category_id
            AND t.transaction_date BETWEEN p_start_date AND p_end_date
            AND t.type = p_type
        WHERE 
            c.user_id = p_user_id
            AND c.type = p_type
        GROUP BY 
            c.category_id
        ORDER BY 
            total_amount DESC;
    END IF;
END //
DELIMITER ;

-- 18. Create procedure to calculate balance over time
DELIMITER //
CREATE PROCEDURE get_balance_over_time(
    IN p_user_id INT,
    IN p_granularity ENUM('daily', 'weekly', 'monthly'),
    IN p_start_date DATE,
    IN p_end_date DATE
)
BEGIN
    -- Validate user exists
    DECLARE user_exists INT;
    SELECT COUNT(*) INTO user_exists FROM users WHERE user_id = p_user_id;
    
    IF user_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';
    END IF;
    
    -- Validate date range
    IF p_start_date > p_end_date THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Start date must be before end date';
    END IF;
    
    -- Generate time series based on granularity
    IF p_granularity = 'daily' THEN
        SELECT 
            date_series.date AS period,
            COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) AS income,
            COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS expense,
            COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE -t.amount END), 0) AS net_balance
        FROM (
            SELECT DATE(p_start_date + INTERVAL seq DAY) AS date
            FROM (
                SELECT a.N + b.N*10 + c.N*100 AS seq
                FROM 
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b,
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) c
                WHERE (a.N + b.N*10 + c.N*100) <= DATEDIFF(p_end_date, p_start_date)
            ) seq
            WHERE DATE(p_start_date + INTERVAL seq DAY) <= p_end_date
        ) date_series
        LEFT JOIN transactions t ON DATE(t.transaction_date) = date_series.date AND t.user_id = p_user_id
        GROUP BY date_series.date
        ORDER BY date_series.date;
        
    ELSEIF p_granularity = 'weekly' THEN
        SELECT 
            YEARWEEK(date_series.date) AS period,
            MIN(date_series.date) AS week_start,
            MAX(date_series.date) AS week_end,
            COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) AS income,
            COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS expense,
            COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE -t.amount END), 0) AS net_balance
        FROM (
            SELECT DATE(p_start_date + INTERVAL seq DAY) AS date
            FROM (
                SELECT a.N + b.N*10 + c.N*100 AS seq
                FROM 
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b,
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) c
                WHERE (a.N + b.N*10 + c.N*100) <= DATEDIFF(p_end_date, p_start_date)
            ) seq
            WHERE DATE(p_start_date + INTERVAL seq DAY) <= p_end_date
        ) date_series
        LEFT JOIN transactions t ON YEARWEEK(t.transaction_date) = YEARWEEK(date_series.date) AND t.user_id = p_user_id
        GROUP BY YEARWEEK(date_series.date)
        ORDER BY YEARWEEK(date_series.date);
        
    ELSE -- monthly
        SELECT 
            EXTRACT(YEAR_MONTH FROM date_series.date) AS period,
            MIN(date_series.date) AS month_start,
            MAX(date_series.date) AS month_end,
            COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) AS income,
            COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS expense,
            COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE -t.amount END), 0) AS net_balance
        FROM (
            SELECT DATE(p_start_date + INTERVAL seq DAY) AS date
            FROM (
                SELECT a.N + b.N*10 + c.N*100 AS seq
                FROM 
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b,
                    (SELECT 0 AS N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) c
                WHERE (a.N + b.N*10 + c.N*100) <= DATEDIFF(p_end_date, p_start_date)
            ) seq
            WHERE DATE(p_start_date + INTERVAL seq DAY) <= p_end_date
        ) date_series
        LEFT JOIN transactions t ON EXTRACT(YEAR_MONTH FROM t.transaction_date) = EXTRACT(YEAR_MONTH FROM date_series.date) AND t.user_id = p_user_id
        GROUP BY EXTRACT(YEAR_MONTH FROM date_series.date)
        ORDER BY EXTRACT(YEAR_MONTH FROM date_series.date);
    END IF;
END //
DELIMITER ;

-- Insert sample users
INSERT INTO users (username, email, full_name, registration_date, last_login, is_active) VALUES
('yuvii', 'yuvii@gmail.com', 'Yuvii Jadhav', '2025-01-01 10:00:00', '2025-06-15 14:30:00', TRUE),
('sumit', 'sumit@gmail.com', 'Sumit', '2025-01-05 11:15:00', '2025-06-14 09:45:00', TRUE),
('harshit', 'harshit@gmail.com', 'Harshit', '2025-02-10 15:20:00', '2025-06-10 16:20:00', TRUE),
('kartik', 'kartik@gmail.com', 'Kartik', '2025-03-15 09:30:00', '2025-06-12 11:10:00', TRUE),
('prem', 'prem@gmail.com', 'Prem', '2025-04-20 14:00:00', '2025-06-11 13:25:00', FALSE);

-- Insert sample categories for all users
INSERT INTO categories (user_id, name, description, type, parent_category_id, is_active) VALUES
-- User 1 (Yuvii Jadhav)
(1, 'Salary', 'Monthly salary', 'income', NULL, TRUE),
(1, 'Freelance', 'Freelance work income', 'income', NULL, TRUE),
(1, 'Investments', 'Stock and bond returns', 'income', NULL, TRUE),
(1, 'Dividends', 'Investment dividends', 'income', 3, TRUE),
(1, 'Bonus', 'Annual bonus', 'income', 1, TRUE),
(1, 'Housing', 'Rent/mortgage payments', 'expense', NULL, TRUE),
(1, 'Utilities', 'Electricity, water, etc.', 'expense', NULL, TRUE),
(1, 'Groceries', 'Food and household items', 'expense', NULL, TRUE),
(1, 'Transportation', 'Car and public transport', 'expense', NULL, TRUE),
(1, 'Entertainment', 'Movies, events, etc.', 'expense', NULL, TRUE),
(1, 'Dining Out', 'Restaurants and cafes', 'expense', NULL, TRUE),
(1, 'Healthcare', 'Medical expenses', 'expense', NULL, TRUE),
(1, 'Education', 'Courses and books', 'expense', NULL, TRUE),
(1, 'Rent', 'Monthly apartment rent', 'expense', 6, TRUE),
(1, 'Electricity', 'Monthly electricity bill', 'expense', 7, TRUE),

-- User 2 (Sumit)
(2, 'Salary', 'Primary job salary', 'income', NULL, TRUE),
(2, 'Side Hustle', 'Side project income', 'income', NULL, TRUE),
(2, 'Rental', 'Property rental income', 'income', NULL, TRUE),
(2, 'Housing', 'Housing costs', 'expense', NULL, TRUE),
(2, 'Food', 'All food expenses', 'expense', NULL, TRUE),
(2, 'Transport', 'Transportation costs', 'expense', NULL, TRUE),
(2, 'Subscriptions', 'Streaming and other subscriptions', 'expense', NULL, TRUE),

-- User 3 (Harshit)
(3, 'Paycheck', 'Bi-weekly paycheck', 'income', NULL, TRUE),
(3, 'Consulting', 'Consulting fees', 'income', NULL, TRUE),
(3, 'Mortgage', 'House mortgage', 'expense', NULL, TRUE),
(3, 'Car', 'Car payments and maintenance', 'expense', NULL, TRUE),
(3, 'Insurance', 'Various insurance payments', 'expense', NULL, TRUE),

-- User 4 (Kartik)
(4, 'Salary', 'Monthly paycheck', 'income', NULL, TRUE),
(4, 'Investments', 'Stock market returns', 'income', NULL, TRUE),
(4, 'Rent', 'Apartment rental income', 'income', NULL, TRUE),
(4, 'Housing', 'Mortgage and utilities', 'expense', NULL, TRUE),
(4, 'Transportation', 'Car and public transit', 'expense', NULL, TRUE),
(4, 'Education', 'Professional development', 'expense', NULL, TRUE),
(4, 'Travel', 'Vacation expenses', 'expense', NULL, TRUE),

-- User 5 (Prem)
(5, 'Salary', 'Monthly paycheck', 'income', NULL, TRUE),
(5, 'Freelance', 'Contract work', 'income', NULL, TRUE),
(5, 'Rent', 'Apartment rent', 'expense', NULL, TRUE),
(5, 'Utilities', 'Electricity and internet', 'expense', NULL, TRUE),
(5, 'Food', 'Groceries and dining', 'expense', NULL, TRUE),
(5, 'Entertainment', 'Movies and events', 'expense', NULL, TRUE);

-- Insert sample transactions for all users with 2025 dates
-- User 1 (Yuvii Jadhav) transactions
INSERT INTO transactions (user_id, category_id, amount, transaction_date, description, type) VALUES
-- Income
(1, 1, 5000.00, '2025-01-05', 'Monthly salary', 'income'),
(1, 2, 1200.50, '2025-01-10', 'Freelance project A', 'income'),
(1, 4, 350.75, '2025-01-15', 'Quarterly dividends', 'income'),
(1, 1, 5000.00, '2025-02-05', 'Monthly salary', 'income'),
(1, 2, 800.25, '2025-02-12', 'Freelance project B', 'income'),
(1, 5, 2000.00, '2025-02-20', 'Annual bonus', 'income'),
(1, 1, 5000.00, '2025-03-05', 'Monthly salary', 'income'),
(1, 2, 1500.00, '2025-03-15', 'Freelance project C', 'income'),

-- Expenses
(1, 6, 1500.00, '2025-01-01', 'Monthly rent', 'expense'),
(1, 7, 120.50, '2025-01-03', 'Electricity bill', 'expense'),
(1, 8, 450.75, '2025-01-05', 'Weekly groceries', 'expense'),
(1, 9, 85.25, '2025-01-08', 'Gas for car', 'expense'),
(1, 10, 65.00, '2025-01-12', 'Movie tickets', 'expense'),
(1, 11, 120.50, '2025-01-15', 'Dinner out', 'expense');

-- User 2 (Sumit) transactions
INSERT INTO transactions (user_id, category_id, amount, transaction_date, description, type) VALUES
-- Income
(2, 16, 4500.00, '2025-01-05', 'Monthly salary', 'income'),
(2, 17, 800.00, '2025-01-12', 'Side project payment', 'income'),
(2, 18, 1200.00, '2025-01-20', 'Rental income', 'income'),

-- Expenses
(2, 19, 1200.00, '2025-01-01', 'Apartment rent', 'expense'),
(2, 20, 350.50, '2025-01-03', 'Grocery shopping', 'expense'),
(2, 21, 120.75, '2025-01-08', 'Public transport', 'expense'),
(2, 22, 25.99, '2025-01-10', 'Streaming service', 'expense');

-- User 3 (Harshit) transactions
INSERT INTO transactions (user_id, category_id, amount, transaction_date, description, type) VALUES
-- Income
(3, 23, 3800.00, '2025-01-07', 'Bi-weekly paycheck', 'income'),
(3, 23, 3800.00, '2025-01-21', 'Bi-weekly paycheck', 'income'),
(3, 24, 1500.00, '2025-01-15', 'Consulting project', 'income'),

-- Expenses
(3, 25, 2200.00, '2025-01-01', 'Mortgage payment', 'expense'),
(3, 26, 450.00, '2025-01-05', 'Car payment', 'expense'),
(3, 27, 250.00, '2025-01-10', 'Car insurance', 'expense');

-- User 4 (Kartik) transactions
INSERT INTO transactions (user_id, category_id, amount, transaction_date, description, type) VALUES
-- Income
(4, 28, 5200.00, '2025-01-05', 'Monthly salary', 'income'),
(4, 29, 750.50, '2025-01-15', 'Investment dividends', 'income'),
(4, 30, 1200.00, '2025-01-20', 'Rental income', 'income'),

-- Expenses
(4, 31, 1800.00, '2025-01-01', 'Mortgage payment', 'expense'),
(4, 32, 350.00, '2025-01-03', 'Car payment', 'expense'),
(4, 33, 450.00, '2025-01-10', 'Online course', 'expense');

-- User 5 (Prem) transactions
INSERT INTO transactions (user_id, category_id, amount, transaction_date, description, type) VALUES
-- Income
(5, 35, 4800.00, '2025-01-07', 'Monthly salary', 'income'),
(5, 36, 1200.00, '2025-01-15', 'Freelance project', 'income'),

-- Expenses
(5, 37, 1400.00, '2025-01-01', 'Apartment rent', 'expense'),
(5, 38, 150.00, '2025-01-03', 'Electricity bill', 'expense'),
(5, 39, 450.00, '2025-01-05', 'Grocery shopping', 'expense'),
(5, 40, 120.00, '2025-01-12', 'Concert tickets', 'expense');

-- 22. Verify all tables have data
SELECT 'Users' AS table_name, COUNT(*) AS record_count FROM users
UNION ALL
SELECT 'Categories', COUNT(*) FROM categories
UNION ALL
SELECT 'Transactions', COUNT(*) FROM transactions
UNION ALL
SELECT 'Audit Log', COUNT(*) FROM transaction_audit_log;

-- 23. Test the audit log functionality
-- First, make some test transactions
INSERT INTO transactions (user_id, category_id, amount, description, type)
VALUES (1, 1, 5000.00, 'Test salary insert', 'income');

UPDATE transactions 
SET amount = 5500.00 
WHERE transaction_id = LAST_INSERT_ID();

DELETE from transactions 
WHERE transaction_id = LAST_INSERT_ID();

-- 24. Check the audit log
SELECT * FROM transaction_audit_log 
ORDER BY action_timestamp DESC 
LIMIT 10;

-- 25. Test views and procedures
SELECT * FROM users;

-- View all categories for user 1
SELECT * FROM categories WHERE user_id = 1;

-- View all transactions for user 1
SELECT * FROM transactions WHERE user_id = 1 ORDER BY transaction_date DESC;

-- View monthly summary for user 1
SELECT * FROM monthly_summary WHERE user_id = 1;

-- View current balances for all users
SELECT * FROM user_balances;

-- View top expense categories for user 1
SELECT * FROM top_expense_categories WHERE user_id = 1;

-- View top income categories for user 1
SELECT * FROM top_income_categories WHERE user_id = 1;

-- View category hierarchy for user 1
SELECT * FROM category_hierarchy WHERE user_id = 1;

-- Generate a monthly report for user 1 (June 2025)
CALL generate_monthly_report(1, 2025, 6);

-- Get category totals for user 1 (Jan–June 2025)
CALL get_category_totals(1, '2025-01-01', '2025-06-30', 'both');

-- View balance over time for user 1 (monthly)
CALL get_balance_over_time(1, 'monthly', '2025-01-01', '2025-06-30');