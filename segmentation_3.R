# 데이터 읽기
data_mart <- read.csv('data_mart.csv', fileEncoding = 'CP949')

# 데이터 확인
head(data_mart)
str(data_mart)
summary(data_mart)
colSums(is.na(data_mart))

library(dplyr)
data_mart %>%
  group_by(user_segment) %>%
  summarise(mean_solve_time = mean(avg_solve_time),
            mean_activity_days = mean(activity_days),
            mean_pc = mean(pc_ratio),
            mean_dawn = mean(dawn_ratio),
            mean_morning = mean(morning_ratio),
            mean_afternoon = mean(afternoon_ratio),
            mean_evening = mean(evening_ratio))

# 세그먼트별 요약 통계량 확인
# 문제풀이 시간 & 학습 활동 기간 -> 핵심 학습자가 가장 높음
# pc 플랫폼 사용 비율 -> 저성취 이탈이 가장 높음
# 활동 시간대 비율 -> 새벽 시간 활동이 가장 높은 세그먼트는 저성취 이탈 (오전 학습 비율보다 낮아짐)

# ANOVA - 세그먼트 간 주요 행동 지표 차이 검정
# Tukey 사후 검정 - 차이가 있다면 어떤 세그먼트 간 차이가 존재하는지 추가 분석
model_1 <- aov(avg_solve_time ~ user_segment, data_mart)
summary(model_1)
TukeyHSD(model_1)

model_2 <- aov(activity_days ~ user_segment, data_mart)
summary(model_2)
TukeyHSD(model_2)

model_3 <- aov(pc_ratio ~ user_segment, data_mart)
summary(model_3)
TukeyHSD(model_3)

model_4 <- manova(cbind(dawn_ratio, morning_ratio, afternoon_ratio, evening_ratio) ~ user_segment, data_mart)
summary(model_4)
summary(aov(dawn_ratio ~ user_segment, data_mart)) # 새벽 학습 비율만 세그먼트별 유의미한 차이 존재
summary(aov(morning_ratio ~ user_segment, data_mart))
summary(aov(afternoon_ratio ~ user_segment, data_mart))
summary(aov(evening_ratio ~ user_segment, data_mart))
TukeyHSD(aov(dawn_ratio ~ user_segment, data_mart))
