# Olist E-commerce Performance Dashboard

### 🔗 [Watch Interactive Demo](https://youtu.be/YA2-tyQhSe4)

## 📌 Business Objective
Built an end-to-end analytics solution to track Olist Marketplace performance across Revenue, Logistics, and Customer Satisfaction. The goal was to provide actionable insights into revenue drivers and supply chain bottlenecks for the 2016-2018 period.

## 🛠️ Tech Stack
* **Database:** SQL Server (Data Cleaning & Transformation)
* **Visualization:** Power BI
* **Logic:** Advanced DAX (Time Intelligence, Custom KPIs)
* **Modeling:** Star Schema

## 📊 Key Insights & Recommendations
* **Revenue Concentration:** 78.8% of revenue is driven by Credit Card payments. 
* **Logistics Bottlenecks:** States like MA and CE show the highest delivery delays, impacting customer satisfaction scores.
* **Growth Opportunity:** "Health & Beauty" is the top-performing category, but there's significant room to increase the Average Order Value (AOV) which currently sits at 161.04 against a 175.00 target.

## 📐 Data Model
I implemented a Star Schema to optimize query performance, connecting fact tables (Orders, Payments, Reviews) with dimension tables (Products, Customers, Date, Geolocation).

---
*Note: This project was developed as part of a professional portfolio to demonstrate data storytelling and technical proficiency in the E-commerce domain.*