# 💰 Personal Finance Management System (MySQL Project)

This project is a MySQL-based personal finance management system that tracks user income, expenses, categories, and provides insightful analytics like monthly reports, category totals, and balance trends over time.

---

## 📌 Features

- User registration and login data
- Categorized tracking of income and expenses
- Parent-child category hierarchy
- Auto-logging of insert, update, delete actions via audit log
- Monthly report generation using stored procedures
- Category-wise financial summary
- Visual tracking of monthly income, expense, and net balance

---

## 🗂️ Database Schema

- `users` – Stores user profile and activity
- `categories` – Income/Expense categories (with parent-child support)
- `transactions` – All financial entries
- `transaction_audit_log` – Tracks all changes to `transactions`
- `Views`:
  - `user_balances`
  - `category_hierarchy`
  - `monthly_summary`
  - `top_income_categories`
  - `top_expense_categories`
  - 
- ✅ Table Creation
- ✅ Sample Data Insertion (Users, Categories, Transactions)
- ✅ Audit Trigger Setup
- ✅ View Definitions
- ✅ Stored Procedures:
  - `generate_monthly_report(user_id, year, month)`
  - `get_category_totals(user_id, start_date, end_date, type)`
  - `get_balance_over_time(user_id, interval, start_date, end_date)`

## 🚀 How to Run

1. Clone the repo:
   ```bash
   git clone https://github.com/jadhavyuvraj/personal-finance-db.git
   cd personal-finance-db
