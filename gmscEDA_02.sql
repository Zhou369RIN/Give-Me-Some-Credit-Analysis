-- ============================================================
-- 脚本名称: gmscEDA_02.sql
-- 项目名称: Give Me Some Credit 信用风险分析
-- 数据来源: Kaggle竞赛 "Give Me Some Credit"
-- 目标: 对借款人数据进行探索性数据分析，为构建信用评分卡做准备
-- 作者: 周子惠
-- 日期: 2026-03-08
-- 说明: 所有查询均在 MySQL 环境下运行，数据表名为 training
-- ============================================================

-- 1. 数据概览
-- 目的：验证数据已正确导入，查看目标变量的取值分布，并抽样查看原始记录
USE credit_score;
SELECT DISTINCT SeriousDlqin2yrs FROM training;-- 应返回 0 和 1

-- 计算目标变量分布，了解数据不平衡程度（预期违约占比约6%）
SELECT 
    SeriousDlqin2yrs AS 是否违约,
    COUNT(*) AS 样本数,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM training) * 100, 2) AS 占比_百分比
FROM training
GROUP BY SeriousDlqin2yrs;

-- 随机查看5行数据，确认字段取值正常
SELECT SeriousDlqin2yrs, age, MonthlyIncome FROM training LIMIT 5;

-- 2. 缺失值分析
-- 目的：检查关键字段是否存在缺失值，为后续处理提供依据（填充或剔除）
-- 业务背景：MonthlyIncome 和 NumberOfDependents 在原始数据中存在缺失，需确认填充情况
SELECT 
    COUNT(*) - COUNT(MonthlyIncome) AS 月收入缺失数,
    ROUND((COUNT(*) - COUNT(MonthlyIncome)) / COUNT(*) * 100, 2) AS 月收入缺失率,
    COUNT(*) - COUNT(NumberOfDependents) AS 受抚养人数缺失数,
    ROUND((COUNT(*) - COUNT(NumberOfDependents)) / COUNT(*) * 100, 2) AS 受抚养人数缺失率
FROM training;
-- 预期输出：缺失率均为0（因为数据已预处理）

-- 3. 年龄与违约风险的关系
-- 目的：探索不同年龄段的违约率差异，识别高风险年龄群体
-- 分组依据：根据业务常识将年龄划分为青年(18-30)、中青年(31-50)、中老年(51-70)、老年(70+)
-- 注意：数据中可能存在年龄异常值（如0），已在WHERE中排除
SELECT 
    CASE 
        WHEN age BETWEEN 18 AND 30 THEN '18-30岁'
        WHEN age BETWEEN 31 AND 50 THEN '31-50岁'
        WHEN age BETWEEN 51 AND 70 THEN '51-70岁'
        ELSE '70岁以上'
    END AS 年龄段,
    COUNT(*) AS 人数,
    SUM(SeriousDlqin2yrs) AS 违约人数,
    ROUND(SUM(SeriousDlqin2yrs) / COUNT(*) * 100, 2) AS 违约率_百分比
FROM training
WHERE age >= 18
GROUP BY 年龄段
ORDER BY 违约率_百分比 DESC;
-- 预期输出：年轻群体违约率可能更高

-- 4. 严重逾期次数与违约风险
-- 目的：观察90天以上逾期次数对违约率的影响
-- 阈值说明：原始数据中存在极端值（如98次），这些可能为数据错误，此处先限制在<=10次以聚焦正常范围
-- 后续可单独分析>10次的样本，判断是否需要剔除或特殊处理
SELECT 
    NumberOfTimes90DaysLate AS 90天逾期次数,
    COUNT(*) AS 人数,
    ROUND(SUM(SeriousDlqin2yrs) / COUNT(*) * 100, 2) AS 违约率_百分比
FROM training
WHERE NumberOfTimes90DaysLate <= 10
GROUP BY NumberOfTimes90DaysLate
ORDER BY NumberOfTimes90DaysLate ASC;
-- 预期：随着逾期次数增加，违约率呈上升趋势

-- 5. 可用额度比值分布概况
-- 目的：了解该关键变量在排除极端异常后的集中趋势和离散程度
-- 阈值5的说明：额度使用率通常应在0~1之间，超过5意味着负债远高于额度，可能是数据错误或极端情况
-- 此处先排除以观察正常人群的分布，后续可统计超过5的样本比例
SELECT 
    MIN(RevolvingUtilizationOfUnsecuredLines) AS 最小值,
    MAX(RevolvingUtilizationOfUnsecuredLines) AS 最大值,
    AVG(RevolvingUtilizationOfUnsecuredLines) AS 平均值,
    STDDEV(RevolvingUtilizationOfUnsecuredLines) AS 标准差
FROM training
WHERE RevolvingUtilizationOfUnsecuredLines < 5;  -- 通常>5可视为异常
-- 预期：均值可能小于1，标准差较大

-- 6. 负债比率极端值初步探查
-- 目的：查看负债比率的最小值附近是否存在异常小值，为后续深入分析提供线索
-- 阈值说明：负债比率 DebtRatio = 每月债务支出/月收入，理论上可大于1。这里先粗略过滤 >100000 的极端值（可能是数据错误）
-- 注意：此处直接按值排序取前20，以观察极小值样本的具体情况，不进行分组，以便看到原始值
SELECT 
    DebtRatio,
    MonthlyIncome,
    NumberOfOpenCreditLinesAndLoans,
    NumberRealEstateLoansOrLines
FROM training
WHERE DebtRatio < 100000
ORDER BY DebtRatio
LIMIT 20;
-- 预期：可能会看到很多接近0的值，需要进一步判断是否为真实无负债

-- 7. 违约与未违约客户的画像对比
-- 目的：比较两类客户在各连续变量上的平均值，找出潜在风险特征
-- 预期：违约客户往往更年轻、收入更低、额度使用率更高、负债比率更高
SELECT 
    SeriousDlqin2yrs,
    COUNT(*) AS 客户数,
    AVG(age) AS 平均年龄,
    AVG(RevolvingUtilizationOfUnsecuredLines) AS 平均额度使用率,
    AVG(DebtRatio) AS 平均负债比率,
    AVG(MonthlyIncome) AS 平均月收入,
    AVG(NumberOfOpenCreditLinesAndLoans) AS 平均信贷数量,
    AVG(NumberRealEstateLoansOrLines) AS 平均房产贷款数量
FROM training
GROUP BY SeriousDlqin2yrs;

-- 8. 风险组合识别：额度使用率与收入的交叉分析
-- 目的：找出高风险客户群，为风控策略提供依据
-- 分段阈值说明：
--   额度使用率：低(≤0.3)、中(0.3~0.8)、高(>0.8)，参考行业常用界限
--   月收入：低(<3000)、中(3000~8000)、高(>8000)，基于数据分布（如中位数/三分位数）划分
-- 预期：高使用率+中低收入组合违约率最高
SELECT 
    CASE 
        WHEN RevolvingUtilizationOfUnsecuredLines <= 0.3 THEN '低使用率'
        WHEN RevolvingUtilizationOfUnsecuredLines <= 0.8 THEN '中使用率'
        ELSE '高使用率'
    END AS 使用率分段,
    CASE 
        WHEN MonthlyIncome < 3000 THEN '低收入'
        WHEN MonthlyIncome < 8000 THEN '中收入'
        ELSE '高收入'
    END AS 收入分段,
    COUNT(*) AS 人数,
    SUM(SeriousDlqin2yrs) AS 违约人数,
    ROUND(SUM(SeriousDlqin2yrs)/COUNT(*)*100,2) AS 违约率
FROM training
WHERE MonthlyIncome IS NOT NULL  -- 确保收入已填充
GROUP BY 使用率分段, 收入分段
ORDER BY 违约率 DESC;

-- 9. 年龄分箱分析（为WOE编码准备）
-- 目的：观察不同年龄段的好/坏样本分布差异，初步判断变量预测能力
-- 分箱说明：当前采用等距划分（按10岁一组），后续可根据WOE值调整分箱
-- 输出指标：坏样本率、坏样本分布、好样本分布，可用于计算IV值
SELECT 
    CASE 
        WHEN age <= 40 THEN '≤40'
        WHEN age <= 50 THEN '41-50'
        WHEN age <= 60 THEN '51-60'
        ELSE '>60'
    END AS 年龄组,
    COUNT(*) AS 总人数,
    SUM(SeriousDlqin2yrs) AS 坏客户数,
    ROUND(SUM(SeriousDlqin2yrs)/COUNT(*)*100,2) AS 坏样本率,
    ROUND((SUM(SeriousDlqin2yrs)/ (SELECT SUM(SeriousDlqin2yrs) FROM training)) * 100,2) AS 坏样本分布,
    ROUND(((COUNT(*)-SUM(SeriousDlqin2yrs))/ (SELECT COUNT(*)-SUM(SeriousDlqin2yrs) FROM training)) * 100,2) AS 好样本分布
FROM training
GROUP BY 年龄组;

-- 10. 微小负债率人群整体情况
-- 目的：针对之前发现的极小值进行深入分析，判断其性质（真实无负债还是数据错误）
-- 阈值0.01：负债比率小于0.01，即每月债务支出不到收入的1%，可视为近似无负债
-- 输出：该人群的规模、违约率、负债比率分布
SELECT 
    COUNT(*) AS 总人数,
    SUM(SeriousDlqin2yrs) AS 违约人数,
    ROUND(AVG(SeriousDlqin2yrs)*100,2) AS 违约率,
    MIN(DebtRatio) AS 最小值,
    MAX(DebtRatio) AS 最大值,
    AVG(DebtRatio) AS 平均值
FROM training
WHERE DebtRatio < 0.01;
-- 预期：若该人群违约率与总体无显著差异，则可能是真实的无负债者

-- 11. 微小负债率 vs 正常负债率：特征对比
-- 目的：通过多维度均值比较，判断微小负债率人群是否具有独特画像（如年龄偏大、收入偏高、无房贷等）
-- 若特征合理，则说明该群体真实存在，建模时应单独分箱
SELECT 
    CASE WHEN DebtRatio < 0.01 THEN '微小负债率' ELSE '正常负债率' END AS 负债率分组,
    COUNT(*) AS 人数,
    AVG(age) AS 平均年龄,
    AVG(MonthlyIncome) AS 平均月收入,
    AVG(RevolvingUtilizationOfUnsecuredLines) AS 平均额度使用率,
    AVG(NumberOfOpenCreditLinesAndLoans) AS 平均信贷账户数,
    AVG(NumberRealEstateLoansOrLines) AS 平均房产贷款数,
    AVG(DebtRatio) AS 平均负债比率
FROM training
GROUP BY 负债率分组;

-- 12. 微小负债率在不同收入层的分布
-- 目的：检查微小负债现象是否集中在特定收入群体，以辅助判断其合理性
-- 预期：如果各收入段占比接近，则微小负债可能普遍存在；若集中在高收入段，则更可能是数据问题
SELECT 
    CASE 
        WHEN MonthlyIncome < 3000 THEN '低收入'
        WHEN MonthlyIncome < 8000 THEN '中收入'
        ELSE '高收入'
    END AS 收入分段,
    COUNT(*) AS 总人数,
    SUM(CASE WHEN DebtRatio < 0.01 THEN 1 ELSE 0 END) AS 微小负债人数,
    ROUND(SUM(CASE WHEN DebtRatio < 0.01 THEN 1 ELSE 0 END)/COUNT(*)*100,2) AS 微小负债占比
FROM training
WHERE MonthlyIncome IS NOT NULL
GROUP BY 收入分段
ORDER BY 微小负债占比 DESC;

-- 13. 微小负债率样本明细
-- 目的：查看具体客户的债务构成，验证“有信贷账户但无负债”的假设
-- 重点关注：房产贷款是否为0、额度使用率是否很低、信贷账户数是否适中
-- 输出：列举100条记录供人工判断
SELECT 
    DebtRatio,
    MonthlyIncome,
    NumberOfOpenCreditLinesAndLoans,
    NumberRealEstateLoansOrLines,
    RevolvingUtilizationOfUnsecuredLines
FROM training
WHERE DebtRatio < 0.01 AND DebtRatio > 0
ORDER BY DebtRatio
LIMIT 100;
-- 预期：大部分样本房产贷款=0，额度使用率接近0

-- ============================================================
-- 分析结论摘要：
-- 1. 数据无缺失，年龄无异常，逾期次数无极端值。
-- 2. 坏客户更年轻、收入更低、额度使用率更高。
-- 3. 高使用率+中低收入组合违约率高达22.46%。
-- 4. 微小负债率人群（约7%）为真实无负债者，建模时应单独分箱。
-- ============================================================