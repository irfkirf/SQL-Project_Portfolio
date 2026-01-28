"""
User Segmentation Module
=========================

Implements RFM (Recency, Frequency, Monetary) analysis and behavioral
segmentation for digital payment users.

Author: Irfan Khan
Date: 2025-10-24
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Tuple
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler


class UserSegmentation:
    """
    User segmentation and RFM analysis for payment data.
    
    Classifies users into behavioral segments based on transaction patterns,
    enabling targeted marketing and product strategies.
    """
    
    def __init__(self, transactions_df: pd.DataFrame):
        """
        Initialize segmentation analyzer.
        
        Parameters:
        -----------
        transactions_df : pd.DataFrame
            Transaction data with user_id, transaction_date, amount columns
        """
        self.transactions = transactions_df.copy()
        self.rfm_scores = None
        self.segments = None
    
    def rfm_analysis(self,
                    user_column: str = 'user_id',
                    date_column: str = 'transaction_date',
                    amount_column: str = 'amount',
                    analysis_date: datetime = None,
                    recency_bins: int = 4,
                    frequency_bins: int = 4,
                    monetary_bins: int = 4) -> pd.DataFrame:
        """
        Perform RFM (Recency, Frequency, Monetary) analysis.
        
        Parameters:
        -----------
        user_column : str
            Column name for user identifier
        date_column : str
            Column name for transaction date
        amount_column : str
            Column name for transaction amount
        analysis_date : datetime, optional
            Date to calculate recency from (defaults to max date in data)
        recency_bins : int
            Number of bins for recency scoring
        frequency_bins : int
            Number of bins for frequency scoring
        monetary_bins : int
            Number of bins for monetary scoring
        
        Returns:
        --------
        pd.DataFrame
            RFM scores and segments for each user
        """
        # Ensure date column is datetime
        self.transactions[date_column] = pd.to_datetime(self.transactions[date_column])
        
        # Use max date if analysis_date not provided
        if analysis_date is None:
            analysis_date = self.transactions[date_column].max()
        
        # Calculate RFM metrics
        rfm = self.transactions.groupby(user_column).agg({
            date_column: lambda x: (analysis_date - x.max()).days,  # Recency
            user_column: 'count',  # Frequency
            amount_column: 'sum'  # Monetary
        }).reset_index()
        
        rfm.columns = [user_column, 'recency', 'frequency', 'monetary']
        
        # Calculate RFM scores (1-4, with 4 being best)
        # Note: For recency, lower is better, so we reverse the scoring
        rfm['r_score'] = pd.qcut(rfm['recency'], recency_bins, labels=[4, 3, 2, 1], duplicates='drop')
        rfm['f_score'] = pd.qcut(rfm['frequency'], frequency_bins, labels=[1, 2, 3, 4], duplicates='drop')
        rfm['m_score'] = pd.qcut(rfm['monetary'], monetary_bins, labels=[1, 2, 3, 4], duplicates='drop')
        
        # Convert to numeric
        rfm['r_score'] = rfm['r_score'].astype(int)
        rfm['f_score'] = rfm['f_score'].astype(int)
        rfm['m_score'] = rfm['m_score'].astype(int)
        
        # Calculate overall RFM score
        rfm['rfm_score'] = rfm['r_score'] + rfm['f_score'] + rfm['m_score']
        
        # Create RFM segment string
        rfm['rfm_segment'] = (
            rfm['r_score'].astype(str) + 
            rfm['f_score'].astype(str) + 
            rfm['m_score'].astype(str)
        )
        
        # Assign segment names
        rfm['segment_name'] = rfm.apply(self._assign_segment_name, axis=1)
        
        self.rfm_scores = rfm
        return rfm
    
    def _assign_segment_name(self, row: pd.Series) -> str:
        """
        Assign descriptive segment name based on RFM scores.
        
        Parameters:
        -----------
        row : pd.Series
            Row with r_score, f_score, m_score
        
        Returns:
        --------
        str
            Segment name
        """
        r, f, m = row['r_score'], row['f_score'], row['m_score']
        
        # Champions: High across all dimensions
        if r >= 4 and f >= 4 and m >= 4:
            return 'Champions'
        
        # Loyal Customers: High frequency and monetary, good recency
        elif f >= 4 and m >= 3 and r >= 3:
            return 'Loyal Customers'
        
        # Potential Loyalists: Recent users with moderate frequency
        elif r >= 3 and f >= 2 and f <= 3:
            return 'Potential Loyalists'
        
        # New Customers: Very recent but low frequency
        elif r >= 4 and f <= 2:
            return 'New Customers'
        
        # At Risk: High value but low recency
        elif m >= 4 and r <= 2:
            return 'At Risk'
        
        # Need Attention: Above average recency, frequency, monetary
        elif r >= 3 and f >= 3 and m >= 3:
            return 'Need Attention'
        
        # Hibernating: Low recency, was somewhat active
        elif r <= 2 and f >= 2:
            return 'Hibernating'
        
        # Lost: Very low recency and frequency
        elif r <= 2 and f <= 2:
            return 'Lost'
        
        # Price Sensitive: Low monetary despite good frequency
        elif f >= 3 and m <= 2:
            return 'Price Sensitive'
        
        else:
            return 'Others'
    
    def create_segment_profiles(self, rfm_df: pd.DataFrame = None) -> pd.DataFrame:
        """
        Create detailed profiles for each segment.
        
        Parameters:
        -----------
        rfm_df : pd.DataFrame, optional
            RFM analysis results (uses stored if not provided)
        
        Returns:
        --------
        pd.DataFrame
            Segment profiles with statistics
        """
        if rfm_df is None:
            if self.rfm_scores is None:
                raise ValueError("Run rfm_analysis() first or provide rfm_df")
            rfm_df = self.rfm_scores
        
        # Calculate segment statistics
        profiles = rfm_df.groupby('segment_name').agg({
            'user_id': 'count',
            'recency': ['mean', 'median'],
            'frequency': ['mean', 'median'],
            'monetary': ['mean', 'median', 'sum'],
            'rfm_score': 'mean'
        }).reset_index()
        
        # Flatten column names
        profiles.columns = [
            'segment', 'user_count', 
            'avg_recency', 'median_recency',
            'avg_frequency', 'median_frequency',
            'avg_monetary', 'median_monetary', 'total_value',
            'avg_rfm_score'
        ]
        
        # Calculate percentages
        total_users = profiles['user_count'].sum()
        total_value = profiles['total_value'].sum()
        
        profiles['pct_users'] = (profiles['user_count'] / total_users * 100).round(2)
        profiles['pct_value'] = (profiles['total_value'] / total_value * 100).round(2)
        
        # Sort by user count
        profiles = profiles.sort_values('user_count', ascending=False)
        
        return profiles
    
    def identify_churn_risk(self, 
                           rfm_df: pd.DataFrame = None,
                           recency_threshold: int = 60,
                           frequency_threshold: int = 5) -> pd.DataFrame:
        """
        Identify users at risk of churning.
        
        Parameters:
        -----------
        rfm_df : pd.DataFrame, optional
            RFM analysis results
        recency_threshold : int
            Days since last transaction to flag as risk
        frequency_threshold : int
            Minimum historical frequency to be considered valuable
        
        Returns:
        --------
        pd.DataFrame
            Users at churn risk with risk scores
        """
        if rfm_df is None:
            if self.rfm_scores is None:
                raise ValueError("Run rfm_analysis() first")
            rfm_df = self.rfm_scores
        
        # Identify at-risk users
        at_risk = rfm_df[
            (rfm_df['recency'] > recency_threshold) & 
            (rfm_df['frequency'] >= frequency_threshold)
        ].copy()
        
        # Calculate risk score (0-100, higher = more risk)
        at_risk['risk_score'] = (
            (at_risk['recency'] / at_risk['recency'].max() * 50) +  # 50% weight on recency
            ((1 - at_risk['r_score'] / 4) * 30) +  # 30% weight on recency score
            ((1 - at_risk['f_score'] / 4) * 20)   # 20% weight on frequency drop
        )
        
        at_risk = at_risk.sort_values('risk_score', ascending=False)
        
        return at_risk[['user_id', 'recency', 'frequency', 'monetary', 
                       'segment_name', 'risk_score']]
    
    def kmeans_segmentation(self,
                           n_clusters: int = 5,
                           features: List[str] = None) -> pd.DataFrame:
        """
        Perform K-means clustering for user segmentation.
        
        Parameters:
        -----------
        n_clusters : int
            Number of clusters to create
        features : List[str], optional
            Features to use for clustering (default: RFM metrics)
        
        Returns:
        --------
        pd.DataFrame
            User clusters with assignments
        """
        if self.rfm_scores is None:
            raise ValueError("Run rfm_analysis() first")
        
        # Default features
        if features is None:
            features = ['recency', 'frequency', 'monetary']
        
        # Prepare data
        X = self.rfm_scores[features].copy()
        
        # Handle any missing values
        X = X.fillna(X.median())
        
        # Standardize features
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        
        # Perform K-means clustering
        kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10)
        clusters = kmeans.fit_predict(X_scaled)
        
        # Add cluster assignments
        result = self.rfm_scores.copy()
        result['cluster'] = clusters
        
        # Calculate cluster centers (in original scale)
        cluster_centers = pd.DataFrame(
            scaler.inverse_transform(kmeans.cluster_centers_),
            columns=features
        )
        cluster_centers['cluster'] = range(n_clusters)
        
        # Merge cluster characteristics
        result = result.merge(
            cluster_centers.add_prefix('cluster_avg_'),
            left_on='cluster',
            right_on='cluster_avg_cluster',
            how='left'
        )
        
        return result
    
    def analyze_segment_channels(self,
                                transactions_df: pd.DataFrame = None,
                                channel_column: str = 'channel') -> pd.DataFrame:
        """
        Analyze channel preferences by segment.
        
        Parameters:
        -----------
        transactions_df : pd.DataFrame
            Transaction data with channel information
        channel_column : str
            Column name for payment channel
        
        Returns:
        --------
        pd.DataFrame
            Channel distribution by segment
        """
        if self.rfm_scores is None:
            raise ValueError("Run rfm_analysis() first")
        
        if transactions_df is None:
            transactions_df = self.transactions
        
        # Merge segments with transactions
        txn_with_segments = transactions_df.merge(
            self.rfm_scores[['user_id', 'segment_name']],
            on='user_id',
            how='left'
        )
        
        # Calculate channel distribution by segment
        channel_dist = txn_with_segments.groupby(
            ['segment_name', channel_column]
        ).size().reset_index(name='transaction_count')
        
        # Calculate percentages within each segment
        segment_totals = channel_dist.groupby('segment_name')[
            'transaction_count'
        ].sum().reset_index(name='segment_total')
        
        channel_dist = channel_dist.merge(segment_totals, on='segment_name')
        channel_dist['pct_of_segment'] = (
            channel_dist['transaction_count'] / channel_dist['segment_total'] * 100
        ).round(2)
        
        # Pivot for better readability
        channel_pivot = channel_dist.pivot(
            index='segment_name',
            columns=channel_column,
            values='pct_of_segment'
        ).fillna(0)
        
        return channel_pivot
    
    def export_segmentation_report(self, filepath: str):
        """
        Export comprehensive segmentation report to Excel.
        
        Parameters:
        -----------
        filepath : str
            Output file path
        """
        if self.rfm_scores is None:
            raise ValueError("Run rfm_analysis() first")
        
        with pd.ExcelWriter(filepath, engine='openpyxl') as writer:
            # Segment profiles
            profiles = self.create_segment_profiles()
            profiles.to_excel(writer, sheet_name='Segment Profiles', index=False)
            
            # Full RFM scores
            self.rfm_scores.to_excel(writer, sheet_name='RFM Scores', index=False)
            
            # At-risk users
            at_risk = self.identify_churn_risk()
            at_risk.to_excel(writer, sheet_name='Churn Risk', index=False)
            
            # Segment distribution
            segment_counts = self.rfm_scores['segment_name'].value_counts().reset_index()
            segment_counts.columns = ['Segment', 'User Count']
            segment_counts.to_excel(writer, sheet_name='Segment Distribution', index=False)
        
        print(f"Segmentation report exported to {filepath}")


def calculate_clv_estimate(rfm_df: pd.DataFrame,
                           avg_margin: float = 0.15,
                           retention_rate: float = 0.85,
                           periods: int = 12) -> pd.DataFrame:
    """
    Estimate Customer Lifetime Value (CLV) based on RFM metrics.
    
    Parameters:
    -----------
    rfm_df : pd.DataFrame
        RFM analysis results
    avg_margin : float
        Average profit margin percentage
    retention_rate : float
        Expected customer retention rate
    periods : int
        Number of periods to project (months)
    
    Returns:
    --------
    pd.DataFrame
        CLV estimates by user
    """
    clv_data = rfm_df.copy()
    
    # Estimate monthly value
    monthly_value = clv_data['monetary'] / (clv_data['frequency'] + 1)
    
    # Calculate CLV using simplified formula
    # CLV = (Average Monthly Value * Margin) * (1 + r + r^2 + ... + r^n)
    # Where r is retention rate and n is periods
    geometric_sum = sum([retention_rate ** i for i in range(periods)])
    
    clv_data['estimated_clv'] = monthly_value * avg_margin * geometric_sum
    clv_data['clv_tier'] = pd.qcut(
        clv_data['estimated_clv'], 
        q=4, 
        labels=['Low', 'Medium', 'High', 'Very High'],
        duplicates='drop'
    )
    
    return clv_data[['user_id', 'segment_name', 'estimated_clv', 'clv_tier']]


if __name__ == '__main__':
    # Example usage
    from transaction_analyzer import generate_sample_data
    
    print("Generating sample data...")
    sample_data = generate_sample_data(n_transactions=50000, n_users=5000)
    
    print("\nInitializing segmentation...")
    segmenter = UserSegmentation(sample_data)
    
    print("\nPerforming RFM analysis...")
    rfm_results = segmenter.rfm_analysis()
    
    print("\nSegment distribution:")
    print(rfm_results['segment_name'].value_counts())
    
    print("\nSegment profiles:")
    profiles = segmenter.create_segment_profiles()
    print(profiles)
    
    print("\nIdentifying churn risk...")
    at_risk = segmenter.identify_churn_risk()
    print(f"Found {len(at_risk)} users at risk of churning")
    print(at_risk.head())
