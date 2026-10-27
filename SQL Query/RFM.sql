SELECT * FROM ucisalesII
SELECT * FROM ucisalesII2010

ALTER TABLE ucisalesII ALTER COLUMN InvoiceDate DATE NULL;

ALTER TABLE ucisalesII2010 ALTER COLUMN InvoiceDate DATE NULL;

UPDATE ucisalesII
SET InvoiceDate = TRY_CONVERT(DATE, InvoiceDate, 103);

UPDATE ucisalesII2010
SET InvoiceDate = TRY_CONVERT(DATE, InvoiceDate, 103);

----COMBINING BOTH TABLES----

DROP TABLE IF EXISTS uci_sales;

SELECT * 
INTO uci_sales
FROM(
SELECT * FROM ucisalesII
UNION
SELECT * FROM ucisalesII2010
)t

SELECT *  FROM uci_sales
WHERE InvoiceDate IS NOT NULL
ORDER BY InvoiceDate ASC

----
 SELECT CONVERT(VARCHAR (10),MIN(InvoiceDate),103) as Min , FORMAT(MAX(InvoiceDate),'dd-MM-yyyy') as max FROM uci_sales
 SELECT MIN (InvoiceDate) as a FROM uci_sales

 SELECT DATEFROMPARTS(YEAR(InvoiceDate),MONTH(InvoiceDate), DAY(InvoiceDate)) FROM uci_sales
    --FORMAT(MIN(DATEFROMPARTS(YEAR(InvoiceDate), DAY(InvoiceDate), MONTH(InvoiceDate))), 'dd-MM-yyyy') AS MinDate,
    --FORMAT(MAX(DATEFROMPARTS(YEAR(InvoiceDate), DAY(InvoiceDate), MONTH(InvoiceDate))), 'dd-MM-yyyy') AS MaxDate
FROM uci_sales;

WITH Daterange AS(
SELECT CAST('2009-12-01' AS DATE) as start
UNION ALL
SELECT DATEADD(day,1,start)
FROM Daterange
WHERE start < '2011-12-31'
)
SELECT start 
INTO calendar
FROM Daterange
OPTION (MAXRECURSION 0)

SELECT * FROM calendar

EXEC sp_rename 'calendar.start', 'calendar_date', 'COLUMN';

---------------------------------------------------------
 


DROP VIEW IF EXISTS cohort;
GO

CREATE VIEW cohort AS (
SELECT Customer_ID,CAST(MIN(InvoiceDate) AS DATE) as firstpurchase,
DATEFROMPARTS( YEAR(min(InvoiceDate)),MONTH(min(InvoiceDate)),1) as CohortDate
FROM clean
GROUP BY Customer_ID
);



DROP VIEW IF EXISTS clean;
GO

CREATE VIEW clean AS (
SELECT * FROM(
SELECT *, ROW_NUMBER() OVER(PARTITION BY Invoice, StockCode,Quantity, InvoiceDate, Customer_ID ORDER BY InvoiceDate ASC) as N 
FROM uci_sales
WHERE Invoice NOT LIKE '%C%'AND
InvoiceDate IS NOT NULL AND 
Customer_Id IS NOT NULL) t
WHERE N =1)

DROP TABLE IF EXISTS clean2;
GO

SELECT c.*, m.CohortDate 
INTO clean2
FROM clean c
INNER JOIN cohort m
ON c.Customer_ID = m.Customer_ID

SELECT * FROM clean2


SELECT DISTINCT( DATEDIFF(MONTH,CohortDate,InvoiceDate)) AS Inde   FROM clean2
ORDER BY Inde
 
-----Pivot Data

SELECT * 
FROM 
(SELECT DISTINCT Customer_ID,CohortDate,DATEDIFF(MONTH,CohortDate,InvoiceDate) AS Inde FROM clean2) t

PIVOT 
( COUNT(Customer_ID)
    FOR Inde IN (
        [0], [1], [2], [3], [4], [5], [6], [7], [8], [9], 
        [10], [11], [12], [13], [14], [15], [16], [17], [18], 
        [19], [20], [21], [22], [23], [24] ))as pivottable;                --Count of Customers


SELECT * 
FROM 
(SELECT CAST((Quantity * Price) AS decimal(10,2)) Total ,CohortDate,DATEDIFF(MONTH,CohortDate,InvoiceDate) AS Inde FROM clean2) t

PIVOT 
( SUM(Total)
    FOR Inde IN (
        [0], [1], [2], [3], [4], [5], [6], [7], [8], [9], 
        [10], [11], [12], [13], [14], [15], [16], [17], [18], 
        [19], [20], [21], [22], [23], [24] ))as pivottable;                --Sum Spend

        --------------------------------------------------------------------------------------------
        ----RFM ANALYSIS------------------

SELECT * FROM clean2;

WITH RFM AS (
    SELECT Customer_ID,
    DATEDIFF( day,MAX(InvoiceDate),'2011-12-31') AS Rencey,
    COUNT (DISTINCT Invoice) AS Frequency,
    CAST(SUM(Quantity * Price)AS DECIMAL(10,2)) AS Monetary
    FROM clean2
    GROUP BY Customer_ID),

RFMscore AS(
    SELECT  
    Customer_ID,
    Rencey,
    Frequency,
    Monetary,
    NTILE(5) OVER( ORDER BY Rencey DESC) as Rescore,
    NTILE(5) OVER( ORDER BY Frequency ) as Frescore,
    NTILE(5) OVER( ORDER BY Monetary ) as Moscore
    FROM RFM
),

RFMcell AS(
SELECT Customer_ID,
Rencey , Rescore,
Frequency , Frescore,
Monetary , Moscore,
(CAST(Rescore AS VARCHAR) + CAST(Frescore AS VARCHAR) + CAST(Moscore AS VARCHAR)) AS RFM_Cell
FROM RFMscore )

SELECT 
    Customer_ID,
    Rencey, Rescore,
    Frequency, Frescore,
    Monetary, Moscore,
    RFM_Cell,
    CASE 
        WHEN Rescore >= 4 AND Frescore >= 4 AND Moscore >= 4 THEN 'Champions'
        WHEN Frescore >= 3 AND Moscore >= 3 THEN 'Loyal Customers'
        WHEN Rescore >= 4 AND Frescore <= 2 THEN 'Potential Loyalists'
        WHEN Rescore = 5 AND Frescore = 1 THEN 'Recent Customers'
        WHEN Rescore <= 2 AND Frescore >= 3 THEN 'At Risk'
        WHEN Rescore <= 2 AND Frescore = 5 AND Moscore = 5 THEN 'Cannot Lose Them'
        WHEN Rescore <= 2 AND Frescore <= 2 THEN 'Hibernating'
        ELSE 'About to Sleep / Other'
    END AS Customer_Segment
FROM RFMcell;
